"""
Tests for PayHere Retrieval & Reconciliation flow:
- Unit tests for PayHereRetrievalClient
- API tests for POST /api/v1/payments/{transaction_id}/reconcile

All PayHere network calls are mocked; no live Sandbox API calls are made.
"""
import pytest
from decimal import Decimal
from uuid import uuid4
from unittest.mock import patch, AsyncMock, MagicMock
import httpx

from httpx import AsyncClient, ASGITransport
import pytest_asyncio

from app.main import app
from app.db.session import get_db
from app.models.user import User
from app.models.bill import Bill
from app.models.payment_method import PaymentMethod
from app.models.transaction import Transaction
from app.core.security import create_access_token
from app.core.exceptions import BusinessLogicError
from app.schemas.payhere import PayHerePaymentRetrievalResult
from app.services.payhere_retrieval import PayHereRetrievalClient
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


async def create_test_data(
    db_session: AsyncSession,
    *,
    bill_status: str = "UNPAID",
    tx_status: str = "PENDING",
    amount: Decimal = Decimal("250.00"),
    currency: str = "LKR",
):
    """Create isolated user -> bill -> payment_method -> transaction."""
    user = User(
        name="Test Reconcile User",
        email=f"reconcile_{uuid4()}@example.com",
        phone=f"+9477{uuid4().int % 10000000:07d}",
        password_hash="hashed_pw",
        is_active=True,
    )
    db_session.add(user)
    await db_session.flush()

    bill = Bill(
        user_id=user.id,
        biller="CEB",
        account_number=f"ACC-{uuid4().hex[:8]}",
        amount_due=amount,
        currency=currency,
        status=bill_status,
    )
    db_session.add(bill)
    await db_session.flush()

    pm = PaymentMethod(
        user_id=user.id,
        provider="Sandbox",
        token_reference=f"tok_{uuid4().hex[:8]}",
        is_default=True,
    )
    db_session.add(pm)
    await db_session.flush()

    tx = Transaction(
        user_id=user.id,
        bill_id=bill.id,
        payment_method_id=pm.id,
        amount=amount,
        currency=currency,
        status=tx_status,
        idempotency_key=f"idem_{uuid4()}",
    )
    db_session.add(tx)
    await db_session.flush()

    return user, bill, pm, tx


# ---------------------------------------------------------------------------
# 1. PayHereRetrievalClient Unit Tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_client_missing_credentials():
    client = PayHereRetrievalClient(app_id=None, app_secret=None)
    with pytest.raises(BusinessLogicError) as exc_info:
        await client.get_access_token()
    assert "not configured" in str(exc_info.value)


@pytest.mark.asyncio
async def test_client_get_access_token_success():
    client = PayHereRetrievalClient(app_id="test_app_id", app_secret="test_app_secret")

    mock_response = MagicMock(spec=httpx.Response)
    mock_response.status_code = 200
    mock_response.json.return_value = {"access_token": "mocked_jwt_token", "expires_in": 3600}

    mock_http_client = AsyncMock(spec=httpx.AsyncClient)
    mock_http_client.post.return_value = mock_response

    token = await client.get_access_token(client=mock_http_client)
    assert token == "mocked_jwt_token"

    mock_http_client.post.assert_called_once()
    call_args, call_kwargs = mock_http_client.post.call_args
    assert call_kwargs["auth"] == ("test_app_id", "test_app_secret")
    assert call_kwargs["data"] == {"grant_type": "client_credentials"}


@pytest.mark.asyncio
async def test_client_get_access_token_http_error():
    client = PayHereRetrievalClient(app_id="test_app_id", app_secret="test_app_secret")

    mock_response = MagicMock(spec=httpx.Response)
    mock_response.status_code = 401

    mock_http_client = AsyncMock(spec=httpx.AsyncClient)
    mock_http_client.post.return_value = mock_response

    with pytest.raises(BusinessLogicError) as exc_info:
        await client.get_access_token(client=mock_http_client)
    assert "Failed to obtain PayHere OAuth token" in str(exc_info.value)


@pytest.mark.asyncio
async def test_client_retrieve_payment_success():
    client = PayHereRetrievalClient(app_id="test_app_id", app_secret="test_app_secret")

    # Mock token
    with patch.object(client, "get_access_token", new_callable=AsyncMock) as mock_get_token:
        mock_get_token.return_value = "token_abc"

        mock_search_res = MagicMock(spec=httpx.Response)
        mock_search_res.status_code = 200
        mock_search_res.json.return_value = {
            "status": 1,
            "data": [
                {
                    "payment_id": "320025199201",
                    "order_id": "order-123",
                    "amount": "250.00",
                    "currency": "LKR",
                    "status": "RECEIVED",
                }
            ],
        }

        mock_http_client = AsyncMock(spec=httpx.AsyncClient)
        mock_http_client.get.return_value = mock_search_res

        res = await client.retrieve_payment("order-123", client=mock_http_client)
        assert res.status == "SUCCESS"
        assert res.provider_reference == "320025199201"
        assert res.amount == Decimal("250.00")
        assert res.currency == "LKR"
        assert res.order_id == "order-123"


@pytest.mark.asyncio
async def test_client_retrieve_payment_not_found():
    client = PayHereRetrievalClient(app_id="test_app_id", app_secret="test_app_secret")

    with patch.object(client, "get_access_token", new_callable=AsyncMock) as mock_get_token:
        mock_get_token.return_value = "token_abc"

        # PayHere returns status -1 or 404
        mock_search_res = MagicMock(spec=httpx.Response)
        mock_search_res.status_code = 200
        mock_search_res.json.return_value = {
            "status": -1,
            "msg": "Payment not found",
            "data": None,
        }

        mock_http_client = AsyncMock(spec=httpx.AsyncClient)
        mock_http_client.get.return_value = mock_search_res

        res = await client.retrieve_payment("order-not-found", client=mock_http_client)
        assert res.status == "NOT_FOUND"


@pytest.mark.asyncio
async def test_client_retrieve_payment_failed():
    client = PayHereRetrievalClient(app_id="test_app_id", app_secret="test_app_secret")

    with patch.object(client, "get_access_token", new_callable=AsyncMock) as mock_get_token:
        mock_get_token.return_value = "token_abc"

        mock_search_res = MagicMock(spec=httpx.Response)
        mock_search_res.status_code = 200
        mock_search_res.json.return_value = {
            "status": -2,
            "data": [
                {
                    "payment_id": "320025199202",
                    "order_id": "order-failed",
                    "amount": "250.00",
                    "currency": "LKR",
                }
            ],
        }

        mock_http_client = AsyncMock(spec=httpx.AsyncClient)
        mock_http_client.get.return_value = mock_search_res

        res = await client.retrieve_payment("order-failed", client=mock_http_client)
        assert res.status == "FAILED"
        assert res.provider_reference == "320025199202"


@pytest.mark.asyncio
async def test_client_retrieve_payment_pending():
    client = PayHereRetrievalClient(app_id="test_app_id", app_secret="test_app_secret")

    with patch.object(client, "get_access_token", new_callable=AsyncMock) as mock_get_token:
        mock_get_token.return_value = "token_abc"

        mock_search_res = MagicMock(spec=httpx.Response)
        mock_search_res.status_code = 200
        mock_search_res.json.return_value = {
            "status": 0,
            "data": [
                {
                    "payment_id": "320025199203",
                    "order_id": "order-pending",
                    "amount": "250.00",
                    "currency": "LKR",
                }
            ],
        }

        mock_http_client = AsyncMock(spec=httpx.AsyncClient)
        mock_http_client.get.return_value = mock_search_res

        res = await client.retrieve_payment("order-pending", client=mock_http_client)
        assert res.status == "PENDING"
        assert res.provider_reference == "320025199203"


@pytest.mark.asyncio
async def test_client_retrieve_payment_unknown_status():
    client = PayHereRetrievalClient(app_id="test_app_id", app_secret="test_app_secret")

    with patch.object(client, "get_access_token", new_callable=AsyncMock) as mock_get_token:
        mock_get_token.return_value = "token_abc"

        mock_search_res = MagicMock(spec=httpx.Response)
        mock_search_res.status_code = 200
        mock_search_res.json.return_value = {"status": 99, "data": []}

        mock_http_client = AsyncMock(spec=httpx.AsyncClient)
        mock_http_client.get.return_value = mock_search_res

        with pytest.raises(BusinessLogicError) as exc_info:
            await client.retrieve_payment("order-99", client=mock_http_client)
        assert "Unknown PayHere retrieval status code" in str(exc_info.value)


# ---------------------------------------------------------------------------
# 2. API Endpoint Tests (POST /api/v1/payments/{transaction_id}/reconcile)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_api_reconcile_success(async_client: AsyncClient, db_session: AsyncSession):
    """
    1. Reconcile SUCCESS:
    - PENDING transaction
    - mocked PayHere retrieval returns SUCCESS
    - transaction becomes SUCCESS
    - provider becomes PAYHERE
    - provider_reference saved
    - associated bill becomes PAID
    - bill.amount_due becomes 0.00
    """
    user, bill, pm, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    mock_result = PayHerePaymentRetrievalResult(
        status="SUCCESS",
        provider_reference="PH-REC-99901",
        amount=tx.amount,
        currency=tx.currency,
        order_id=str(tx.id),
    )

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        mock_retrieve.return_value = mock_result
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)

    assert res.status_code == 200, res.text
    data = res.json()
    assert data["status"] == "SUCCESS"
    assert data["provider"] == "PAYHERE"
    assert data["provider_reference"] == "PH-REC-99901"

    # Verify database state
    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "SUCCESS"
    assert tx.provider == "PAYHERE"
    assert tx.provider_reference == "PH-REC-99901"
    assert bill.status == "PAID"
    assert bill.amount_due == Decimal("0.00")


@pytest.mark.asyncio
async def test_api_reconcile_failed(async_client: AsyncClient, db_session: AsyncSession):
    """
    2. Reconcile FAILED:
    - transaction becomes FAILED
    - bill remains unchanged
    """
    user, bill, pm, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    mock_result = PayHerePaymentRetrievalResult(
        status="FAILED",
        provider_reference="PH-REC-FAILED-02",
        amount=tx.amount,
        currency=tx.currency,
        order_id=str(tx.id),
    )

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        mock_retrieve.return_value = mock_result
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)

    assert res.status_code == 200, res.text
    data = res.json()
    assert data["status"] == "FAILED"
    assert data["provider"] == "PAYHERE"
    assert data["provider_reference"] == "PH-REC-FAILED-02"

    # Verify database state
    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "FAILED"
    assert tx.provider == "PAYHERE"
    assert tx.provider_reference == "PH-REC-FAILED-02"
    assert bill.status == "UNPAID"
    assert bill.amount_due == Decimal("250.00")


@pytest.mark.asyncio
async def test_api_reconcile_pending(async_client: AsyncClient, db_session: AsyncSession):
    """
    3. Reconcile PENDING:
    - transaction remains PENDING
    """
    user, bill, pm, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    mock_result = PayHerePaymentRetrievalResult(
        status="PENDING",
        provider_reference="PH-REC-PENDING-03",
        amount=tx.amount,
        currency=tx.currency,
        order_id=str(tx.id),
    )

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        mock_retrieve.return_value = mock_result
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)

    assert res.status_code == 200, res.text
    data = res.json()
    assert data["status"] == "PENDING"
    assert data["provider"] == "PAYHERE"

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert bill.status == "UNPAID"
    assert bill.amount_due == Decimal("250.00")


@pytest.mark.asyncio
async def test_api_reconcile_not_found(async_client: AsyncClient, db_session: AsyncSession):
    """
    4. Reconcile NOT_FOUND:
    - transaction remains PENDING
    - bill untouched
    """
    user, bill, pm, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    mock_result = PayHerePaymentRetrievalResult(
        status="NOT_FOUND",
        order_id=str(tx.id),
    )

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        mock_retrieve.return_value = mock_result
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)

    assert res.status_code == 200, res.text
    data = res.json()
    assert data["status"] == "PENDING"

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert bill.status == "UNPAID"
    assert bill.amount_due == Decimal("250.00")


@pytest.mark.asyncio
async def test_api_reconcile_already_success_skips_payhere(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    5. Already SUCCESS:
    - PayHere retrieval client is NOT called
    - transaction stays SUCCESS
    """
    user, bill, pm, tx = await create_test_data(db_session, tx_status="SUCCESS", bill_status="PAID")
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)
        mock_retrieve.assert_not_called()

    assert res.status_code == 200, res.text
    data = res.json()
    assert data["status"] == "SUCCESS"

    await db_session.refresh(tx)
    assert tx.status == "SUCCESS"


@pytest.mark.asyncio
async def test_api_reconcile_already_failed_skips_payhere(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Already FAILED transaction returns unchanged without calling PayHere."""
    user, bill, pm, tx = await create_test_data(db_session, tx_status="FAILED")
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)
        mock_retrieve.assert_not_called()

    assert res.status_code == 200, res.text
    assert res.json()["status"] == "FAILED"


@pytest.mark.asyncio
async def test_api_reconcile_wrong_user_returns_404(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    6. Wrong user:
    - request must not reveal transaction existence (404)
    """
    user_a, bill_a, pm_a, tx_a = await create_test_data(db_session)
    user_b, _, _, _ = await create_test_data(db_session)

    token_b = create_access_token(subject=user_b.id)
    headers = {"Authorization": f"Bearer {token_b}"}

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        res = await async_client.post(f"/api/v1/payments/{tx_a.id}/reconcile", headers=headers)
        mock_retrieve.assert_not_called()

    assert res.status_code == 404
    assert "Transaction not found or does not belong to user." in res.json()["detail"]


@pytest.mark.asyncio
async def test_api_reconcile_amount_mismatch(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    7. Amount mismatch:
    - return controlled error (400)
    - transaction remains unchanged
    - bill remains unchanged
    """
    user, bill, pm, tx = await create_test_data(db_session, amount=Decimal("250.00"))
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    mock_result = PayHerePaymentRetrievalResult(
        status="SUCCESS",
        provider_reference="PH-REC-MISMATCH-AMT",
        amount=Decimal("500.00"),  # mismatch: expected 250.00
        currency=tx.currency,
        order_id=str(tx.id),
    )

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        mock_retrieve.return_value = mock_result
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)

    assert res.status_code == 400
    assert "amount mismatch" in res.json()["detail"]

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert bill.status == "UNPAID"
    assert bill.amount_due == Decimal("250.00")


@pytest.mark.asyncio
async def test_api_reconcile_currency_mismatch(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    8. Currency mismatch:
    - same safety behavior (400, no DB mutation)
    """
    user, bill, pm, tx = await create_test_data(db_session, currency="LKR")
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    mock_result = PayHerePaymentRetrievalResult(
        status="SUCCESS",
        provider_reference="PH-REC-MISMATCH-CURR",
        amount=tx.amount,
        currency="USD",  # mismatch: expected LKR
        order_id=str(tx.id),
    )

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        mock_retrieve.return_value = mock_result
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)

    assert res.status_code == 400
    assert "currency mismatch" in res.json()["detail"]

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert bill.status == "UNPAID"


@pytest.mark.asyncio
async def test_api_reconcile_unknown_retrieval_status(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    9. Unknown PayHere retrieval status:
    - controlled error (400)
    - no mutation
    """
    user, bill, pm, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch.object(PayHereRetrievalClient, "retrieve_payment", new_callable=AsyncMock) as mock_retrieve:
        mock_retrieve.side_effect = BusinessLogicError("Unknown PayHere retrieval status code: 99")
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)

    assert res.status_code == 400
    assert "Unknown PayHere retrieval status code" in res.json()["detail"]

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert bill.status == "UNPAID"


@pytest.mark.asyncio
async def test_api_reconcile_missing_api_credentials(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    10. Missing PAYHERE_API_APP_ID / APP_SECRET:
    - controlled configuration error (400)
    - no DB mutation
    """
    user, bill, pm, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere_retrieval.settings.PAYHERE_API_APP_ID", None), \
         patch("app.services.payhere_retrieval.settings.PAYHERE_API_APP_SECRET", None):
        res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile", headers=headers)

    assert res.status_code == 400
    assert "credentials (APP_ID / APP_SECRET) are not configured" in res.json()["detail"]

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert bill.status == "UNPAID"


@pytest.mark.asyncio
async def test_api_reconcile_unauthenticated(async_client: AsyncClient, db_session: AsyncSession):
    """JWT required: unauthenticated request returns 401."""
    user, bill, pm, tx = await create_test_data(db_session)
    res = await async_client.post(f"/api/v1/payments/{tx.id}/reconcile")
    assert res.status_code == 401
