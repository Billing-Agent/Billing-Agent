"""
Tests for Phase 8A: Read-Only Conversational AI Layer using Google ADK + Gemini.

Covers:
1. Authentication required (401 without JWT)
2. User asks: "Show my bills" -> returns only authenticated user's bills
3. User asks: "How much is my electricity bill?" -> resolves CEB and real bill amount
4. User asks for another user's account number -> must not return another user's bill
5. Multiple matching bills -> clarifies with candidate accounts
6. Unknown biller -> no hallucinated bill, clean not-found response
7. User asks: "Pay my bill" -> refuses payment execution, PaymentService never called
8. Tool cannot write to DB -> verifies no transaction/bill mutation occurs
9. Missing Gemini API key -> controlled configuration error (HTTP 400)
10. All Gemini/ADK calls mocked -> zero outbound network calls to live Gemini API
"""
import pytest
from decimal import Decimal
from uuid import uuid4
from unittest.mock import patch, AsyncMock, MagicMock
from sqlalchemy import select

from httpx import AsyncClient, ASGITransport
import pytest_asyncio

from google.adk.events import Event
from google.genai import types

from app.main import app
from app.db.session import get_db
from app.models.user import User
from app.models.bill import Bill
from app.models.transaction import Transaction
from app.core.security import create_access_token
from app.agent.context import BillingAgentContext
from app.agent.tools.bill_tools import BillTools
from app.agent.billing_agent import BillingAgent
from app.services.billing import BillingService
from app.services.payment import PaymentService
from sqlalchemy.ext.asyncio import AsyncSession


# ---------------------------------------------------------------------------
# Fixtures & Helpers
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


async def create_user_and_bills(
    db_session: AsyncSession,
    *,
    user_name: str = "Test User",
    bills_data: list = None,
):
    """Helper to create a user and associated bills."""
    user = User(
        name=user_name,
        email=f"agent_user_{uuid4()}@example.com",
        phone=f"+9477{uuid4().int % 10000000:07d}",
        password_hash="hash",
        is_active=True,
    )
    db_session.add(user)
    await db_session.flush()

    bills = []
    if bills_data is None:
        bills_data = [
            {"biller": "CEB", "account_number": f"ACC-CEB-{uuid4().hex[:6]}", "amount_due": Decimal("1850.00"), "currency": "LKR", "status": "UNPAID"},
        ]

    for bd in bills_data:
        bill = Bill(
            user_id=user.id,
            biller=bd["biller"],
            account_number=bd["account_number"],
            amount_due=bd["amount_due"],
            currency=bd.get("currency", "LKR"),
            status=bd.get("status", "UNPAID"),
            customer_name=bd.get("customer_name", user_name),
        )
        db_session.add(bill)
        bills.append(bill)

    await db_session.flush()
    return user, bills


# ---------------------------------------------------------------------------
# Unit Tests for BillTools
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_tools_get_user_bills(db_session: AsyncSession):
    """Tool 1: get_user_bills returns only the authenticated user's bills with safe fields."""
    user1, bills1 = await create_user_and_bills(
        db_session,
        bills_data=[
            {"biller": "CEB", "account_number": "11111", "amount_due": Decimal("1200.00")},
            {"biller": "WATER", "account_number": "22222", "amount_due": Decimal("650.00")},
        ],
    )
    user2, bills2 = await create_user_and_bills(
        db_session,
        bills_data=[
            {"biller": "CEB", "account_number": "33333", "amount_due": Decimal("4000.00")},
        ],
    )

    billing_service = BillingService(db_session)
    context1 = BillingAgentContext(
        authenticated_user_id=user1.id,
        db=db_session,
        billing_service=billing_service,
    )
    tools1 = BillTools(context1)

    result = await tools1.get_user_bills()
    assert result["status"] == "success"
    assert result["count"] == 2
    account_numbers = [b["account_number"] for b in result["bills"]]
    assert "11111" in account_numbers
    assert "22222" in account_numbers
    assert "33333" not in account_numbers  # user2's bill excluded!

    # Check safe fields
    b = result["bills"][0]
    assert "id" in b
    assert "biller" in b
    assert "account_number" in b
    assert "amount_due" in b
    assert "currency" in b
    assert "status" in b
    assert "user_id" not in b  # internal user_id is never exposed


@pytest.mark.asyncio
async def test_tools_get_bill_by_id_ownership_enforced(db_session: AsyncSession):
    """Tool 2: get_bill_by_id enforces user ownership; fails on other user's bill."""
    user1, bills1 = await create_user_and_bills(db_session)
    user2, bills2 = await create_user_and_bills(db_session)

    billing_service = BillingService(db_session)
    context1 = BillingAgentContext(
        authenticated_user_id=user1.id,
        db=db_session,
        billing_service=billing_service,
    )
    tools1 = BillTools(context1)

    # User 1 looks up own bill -> success
    res_own = await tools1.get_bill_by_id(str(bills1[0].id))
    assert res_own["status"] == "success"
    assert res_own["bill"]["account_number"] == bills1[0].account_number

    # User 1 attempts to look up User 2's bill -> not_found
    res_other = await tools1.get_bill_by_id(str(bills2[0].id))
    assert res_other["status"] == "not_found"


@pytest.mark.asyncio
async def test_tools_find_bill_biller_normalization(db_session: AsyncSession):
    """Tool 3: find_bill normalizes 'electricity' -> 'CEB' and 'water' -> 'WATER'."""
    user, bills = await create_user_and_bills(
        db_session,
        bills_data=[
            {"biller": "CEB", "account_number": "ELEC-100", "amount_due": Decimal("1850.00")},
            {"biller": "WATER", "account_number": "WAT-200", "amount_due": Decimal("900.00")},
        ],
    )
    billing_service = BillingService(db_session)
    context = BillingAgentContext(
        authenticated_user_id=user.id,
        db=db_session,
        billing_service=billing_service,
    )
    tools = BillTools(context)

    # Search with natural language query containing "electricity"
    res_elec = await tools.find_bill(query="How much is my electricity bill?")
    assert res_elec["status"] == "found"
    assert res_elec["bill"]["biller"] == "CEB"
    assert res_elec["bill"]["amount_due"] == "1850.00"

    # Search with biller="power"
    res_power = await tools.find_bill(biller="power")
    assert res_power["status"] == "found"
    assert res_power["bill"]["biller"] == "CEB"

    # Search with "water"
    res_water = await tools.find_bill(query="Show my water bill")
    assert res_water["status"] == "found"
    assert res_water["bill"]["biller"] == "WATER"


@pytest.mark.asyncio
async def test_tools_find_bill_multiple_matches_asks_clarification(db_session: AsyncSession):
    """Tool 3: find_bill returns multiple_matches when user has multiple bills for same biller."""
    user, bills = await create_user_and_bills(
        db_session,
        bills_data=[
            {"biller": "CEB", "account_number": "CEB-HOME", "amount_due": Decimal("1500.00")},
            {"biller": "CEB", "account_number": "CEB-OFFICE", "amount_due": Decimal("3200.00")},
        ],
    )
    billing_service = BillingService(db_session)
    context = BillingAgentContext(
        authenticated_user_id=user.id,
        db=db_session,
        billing_service=billing_service,
    )
    tools = BillTools(context)

    res = await tools.find_bill(query="How much is my electricity bill?")
    assert res["status"] == "multiple_matches"
    assert res["count"] == 2
    accounts = [b["account_number"] for b in res["bills"]]
    assert "CEB-HOME" in accounts
    assert "CEB-OFFICE" in accounts

    # Providing specific account resolves ambiguity
    res_specific = await tools.find_bill(query="Show CEB bill for account CEB-HOME")
    assert res_specific["status"] == "found"
    assert res_specific["bill"]["account_number"] == "CEB-HOME"


@pytest.mark.asyncio
async def test_tools_find_bill_unknown_biller(db_session: AsyncSession):
    """Tool 3: find_bill returns not_found for unknown/unregistered biller."""
    user, bills = await create_user_and_bills(
        db_session,
        bills_data=[{"biller": "CEB", "account_number": "12345", "amount_due": Decimal("100.00")}],
    )
    billing_service = BillingService(db_session)
    context = BillingAgentContext(
        authenticated_user_id=user.id,
        db=db_session,
        billing_service=billing_service,
    )
    tools = BillTools(context)

    res = await tools.find_bill(biller="NON_EXISTENT_BILLER")
    assert res["status"] == "not_found"


# ---------------------------------------------------------------------------
# API Endpoint Tests (POST /api/v1/agent/chat)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_api_chat_authentication_required(async_client: AsyncClient):
    """1. POST /agent/chat without JWT returns 401."""
    res = await async_client.post("/api/v1/agent/chat", json={"message": "Show my bills"})
    assert res.status_code == 401


@pytest.mark.asyncio
async def test_api_chat_show_my_bills(async_client: AsyncClient, db_session: AsyncSession):
    """2. User asks 'Show my bills' -> Agent calls get_user_bills and returns user bills."""
    user, bills = await create_user_and_bills(
        db_session,
        bills_data=[{"biller": "CEB", "account_number": "ACC-991", "amount_due": Decimal("1850.00")}],
    )
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    async def mock_run_async(*args, **kwargs):
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(function_call=types.FunctionCall(name="get_user_bills", args={}))],
            )
        )
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(text="You have 1 bill: CEB account ACC-991 with an amount due of LKR 1,850.00.")],
            )
        )

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", "mock_key"), \
         patch("app.agent.billing_agent.InMemoryRunner.run_async", side_effect=mock_run_async):
        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "Show my bills"},
            headers=headers,
        )

    assert res.status_code == 200, res.text
    data = res.json()
    assert "ACC-991" in data["message"]
    assert "1,850.00" in data["message"]
    assert data["tool_calls"] is not None
    assert data["tool_calls"][0]["name"] == "get_user_bills"


@pytest.mark.asyncio
async def test_api_chat_how_much_is_electricity_bill(async_client: AsyncClient, db_session: AsyncSession):
    """3. User asks 'How much is my electricity bill?' -> resolves CEB and returns real bill amount."""
    user, bills = await create_user_and_bills(
        db_session,
        bills_data=[{"biller": "CEB", "account_number": "12346", "amount_due": Decimal("1850.00")}],
    )
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    async def mock_run_async(*args, **kwargs):
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(function_call=types.FunctionCall(name="find_bill", args={"query": "electricity bill"}))],
            )
        )
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(text="Your CEB bill for account 12346 is LKR 1,850.00.")],
            )
        )

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", "mock_key"), \
         patch("app.agent.billing_agent.InMemoryRunner.run_async", side_effect=mock_run_async):
        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "How much is my electricity bill?"},
            headers=headers,
        )

    assert res.status_code == 200, res.text
    data = res.json()
    assert "12346" in data["message"]
    assert "1,850.00" in data["message"]


@pytest.mark.asyncio
async def test_api_chat_cannot_access_another_users_bill(async_client: AsyncClient, db_session: AsyncSession):
    """4. User asks for another user's account number -> must not return another user's bill."""
    user_a, bills_a = await create_user_and_bills(
        db_session,
        user_name="User A",
        bills_data=[{"biller": "CEB", "account_number": "USER-A-ACC", "amount_due": Decimal("500.00")}],
    )
    user_b, bills_b = await create_user_and_bills(
        db_session,
        user_name="User B",
        bills_data=[{"biller": "CEB", "account_number": "USER-B-ACC", "amount_due": Decimal("9999.00")}],
    )
    token_a = create_access_token(subject=user_a.id)
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # User A queries tool with User B's account
    billing_service = BillingService(db_session)
    context_a = BillingAgentContext(authenticated_user_id=user_a.id, db=db_session, billing_service=billing_service)
    tools_a = BillTools(context_a)
    lookup_res = await tools_a.find_bill(account_number="USER-B-ACC")
    assert lookup_res["status"] == "not_found"

    # Test via API
    async def mock_run_async(*args, **kwargs):
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(text="No bill found for account USER-B-ACC in your account.")],
            )
        )

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", "mock_key"), \
         patch("app.agent.billing_agent.InMemoryRunner.run_async", side_effect=mock_run_async):
        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "What is the amount for account USER-B-ACC?"},
            headers=headers_a,
        )

    assert res.status_code == 200
    assert "No bill found" in res.json()["message"]
    assert "9999.00" not in res.json()["message"]


@pytest.mark.asyncio
async def test_api_chat_multiple_matching_bills_clarifies(async_client: AsyncClient, db_session: AsyncSession):
    """5. Multiple matching bills -> Agent asks user to clarify."""
    user, bills = await create_user_and_bills(
        db_session,
        bills_data=[
            {"biller": "CEB", "account_number": "1001", "amount_due": Decimal("1000.00")},
            {"biller": "CEB", "account_number": "1002", "amount_due": Decimal("2000.00")},
        ],
    )
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    async def mock_run_async(*args, **kwargs):
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(text="You have 2 CEB bills: Account 1001 (LKR 1,000.00) and Account 1002 (LKR 2,000.00). Which one would you like to check?")],
            )
        )

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", "mock_key"), \
         patch("app.agent.billing_agent.InMemoryRunner.run_async", side_effect=mock_run_async):
        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "Show my CEB bill"},
            headers=headers,
        )

    assert res.status_code == 200
    assert "Which one" in res.json()["message"]


@pytest.mark.asyncio
async def test_api_chat_unknown_biller(async_client: AsyncClient, db_session: AsyncSession):
    """6. Unknown biller -> No hallucinated bill, returns not found message."""
    user, bills = await create_user_and_bills(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    async def mock_run_async(*args, **kwargs):
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(text="I could not find any bill under 'Netflix' in your registered bills.")],
            )
        )

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", "mock_key"), \
         patch("app.agent.billing_agent.InMemoryRunner.run_async", side_effect=mock_run_async):
        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "Show my Netflix bill"},
            headers=headers,
        )

    assert res.status_code == 200
    assert "could not find" in res.json()["message"]


@pytest.mark.asyncio
async def test_api_chat_pay_bill_refusal_does_not_call_payment_service(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    7. User asks: 'Pay my bill'
    Agent refuses payment execution and does NOT call PaymentService.
    """
    user, bills = await create_user_and_bills(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    refusal_text = "This assistant can currently view bill information, but payment execution is not enabled yet."

    async def mock_run_async(*args, **kwargs):
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(text=refusal_text)],
            )
        )

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", "mock_key"), \
         patch("app.agent.billing_agent.InMemoryRunner.run_async", side_effect=mock_run_async), \
         patch.object(PaymentService, "prepare_payment", new_callable=AsyncMock) as mock_prepare, \
         patch.object(PaymentService, "initiate_payment", new_callable=AsyncMock) as mock_initiate:

        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "Pay my bill now"},
            headers=headers,
        )

        mock_prepare.assert_not_called()
        mock_initiate.assert_not_called()

    assert res.status_code == 200
    assert refusal_text in res.json()["message"]


@pytest.mark.asyncio
async def test_api_chat_tool_cannot_write_to_db(async_client: AsyncClient, db_session: AsyncSession):
    """
    8. Tool cannot write to DB:
    Verify no transaction or bill mutation occurs during or after chat.
    """
    user, bills = await create_user_and_bills(
        db_session,
        bills_data=[{"biller": "CEB", "account_number": "ACC-SAFE-1", "amount_due": Decimal("500.00"), "status": "UNPAID"}],
    )
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    # Count transactions before
    tx_count_before = len((await db_session.execute(select(Transaction))).scalars().all())

    async def mock_run_async(*args, **kwargs):
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(function_call=types.FunctionCall(name="get_user_bills", args={}))],
            )
        )
        yield Event(
            content=types.Content(
                role="model",
                parts=[types.Part(text="Your CEB bill amount is 500.00.")],
            )
        )

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", "mock_key"), \
         patch("app.agent.billing_agent.InMemoryRunner.run_async", side_effect=mock_run_async):
        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "Check my bill"},
            headers=headers,
        )

    assert res.status_code == 200

    # Verify no transactions created
    tx_count_after = len((await db_session.execute(select(Transaction))).scalars().all())
    assert tx_count_after == tx_count_before

    # Verify bill status and amount are completely unchanged
    await db_session.refresh(bills[0])
    assert bills[0].status == "UNPAID"
    assert bills[0].amount_due == Decimal("500.00")


@pytest.mark.asyncio
async def test_api_chat_missing_gemini_api_key_controlled_error(
    async_client: AsyncClient, db_session: AsyncSession
):
    """9. Missing Gemini API key -> controlled configuration error (HTTP 400)."""
    user, bills = await create_user_and_bills(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", None):
        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "Show my bills"},
            headers=headers,
        )

    assert res.status_code == 400
    assert "Gemini API key is not configured" in res.json()["detail"]


@pytest.mark.asyncio
async def test_api_chat_empty_message_validation(async_client: AsyncClient, db_session: AsyncSession):
    """Empty message validation returns 422."""
    user, _ = await create_user_and_bills(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    res = await async_client.post(
        "/api/v1/agent/chat",
        json={"message": ""},
        headers=headers,
    )
    assert res.status_code == 422


@pytest.mark.asyncio
async def test_api_chat_runner_exception_returns_safe_generic_message(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    Verify that when the ADK/Gemini runner raises an internal exception:
    1. The client-facing response does NOT contain the original exception text.
    2. The response contains only the generic safe message:
       'The billing assistant is temporarily unavailable. Please try again.'
    """
    user, bills = await create_user_and_bills(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    secret_leak_text = "INTERNAL_GEMINI_CRASH_SECRET_KEY_URL_LEAK_https://internal.service:8080/token"

    async def mock_run_async_raising(*args, **kwargs):
        raise RuntimeError(secret_leak_text)
        yield

    with patch("app.agent.billing_agent.settings.GEMINI_API_KEY", "mock_key"), \
         patch("app.agent.billing_agent.InMemoryRunner.run_async", side_effect=mock_run_async_raising):
        res = await async_client.post(
            "/api/v1/agent/chat",
            json={"message": "Show my bills"},
            headers=headers,
        )

    assert res.status_code == 400
    data = res.json()
    assert secret_leak_text not in data["detail"]
    assert data["detail"] == "The billing assistant is temporarily unavailable. Please try again."
