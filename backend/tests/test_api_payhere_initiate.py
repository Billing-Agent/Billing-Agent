"""
API tests for POST /api/v1/payments/{transaction_id}/initiate — Milestone 2.

Tests use unittest.mock.patch to inject valid PayHere sandbox credentials into
settings, since the test environment has no real PayHere configuration.
"""
import hashlib
import pytest
from decimal import Decimal
from uuid import uuid4
from unittest.mock import patch, MagicMock

from httpx import AsyncClient, ASGITransport
import pytest_asyncio

from app.main import app
from app.db.session import get_db
from app.models.user import User
from app.models.bill import Bill
from app.models.payment_method import PaymentMethod
from app.models.transaction import Transaction
from app.core.security import create_access_token
from sqlalchemy.ext.asyncio import AsyncSession

# ---------------------------------------------------------------------------
# Constants — fake but well-formed PayHere sandbox credentials for mocking
# ---------------------------------------------------------------------------
MOCK_MERCHANT_ID = "SANDBOX_MERCHANT_123"
MOCK_SECRET = "SANDBOX_SECRET_xyz"
MOCK_NOTIFY_URL = "https://abc.ngrok.io/api/v1/payhere/callback"
MOCK_RETURN_URL = "billingagent://payment/return"
MOCK_CANCEL_URL = "billingagent://payment/cancel"


def _mock_settings():
    m = MagicMock()
    m.PAYHERE_MERCHANT_ID = MOCK_MERCHANT_ID
    m.PAYHERE_SECRET = MOCK_SECRET
    m.PAYHERE_NOTIFY_URL = MOCK_NOTIFY_URL
    m.PAYHERE_RETURN_URL = MOCK_RETURN_URL
    m.PAYHERE_CANCEL_URL = MOCK_CANCEL_URL
    m.PAYHERE_DEFAULT_ADDRESS = "No. 1 Main Street"
    m.PAYHERE_DEFAULT_CITY = "Colombo"
    m.PAYHERE_DEFAULT_COUNTRY = "Sri Lanka"
    return m


def _expected_hash(merchant_id, order_id, amount_str, currency, secret):
    """Recompute the expected PayHere hash independently."""
    def md5up(v): return hashlib.md5(v.encode()).hexdigest().upper()
    hashed_secret = md5up(secret)
    return md5up(merchant_id + order_id + amount_str + currency + hashed_secret)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


_SENTINEL = object()


async def create_test_data(
    db_session: AsyncSession,
    *,
    phone: str | None | object = _SENTINEL,
    bill_status: str = "UNPAID",
    tx_status: str = "PENDING",
):
    """Create user → bill → payment_method → transaction, fully committed to the session."""
    user_phone = f"+9477{uuid4().int % 10000000:07d}" if phone is _SENTINEL else phone
    user = User(
        name="Kasun Perera",
        email=f"kasun_{uuid4()}@example.com",
        phone=user_phone,
        password_hash="hash",
        is_active=True,
    )
    db_session.add(user)
    await db_session.flush()

    bill = Bill(
        user_id=user.id,
        biller="CEB",
        account_number="123456",
        amount_due=Decimal("250.00"),
        currency="LKR",
        status=bill_status,
    )
    db_session.add(bill)
    await db_session.flush()

    pm = PaymentMethod(
        user_id=user.id,
        provider="Sandbox",
        token_reference="tok_xyz",
        is_default=True,
    )
    db_session.add(pm)
    await db_session.flush()

    tx = Transaction(
        user_id=user.id,
        bill_id=bill.id,
        payment_method_id=pm.id,
        amount=bill.amount_due,
        currency="LKR",
        status=tx_status,
        idempotency_key=f"idem_{uuid4()}",
    )
    db_session.add(tx)
    await db_session.flush()

    return user, bill, pm, tx


# ---------------------------------------------------------------------------
# Success path
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_initiate_success_returns_all_required_fields(
    async_client: AsyncClient, db_session: AsyncSession
):
    user, bill, pm, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 200, res.text
    data = res.json()

    required_fields = [
        "merchant_id", "order_id", "items", "currency", "amount",
        "first_name", "last_name", "email", "phone",
        "address", "city", "country",
        "return_url", "cancel_url", "notify_url", "hash",
    ]
    for field in required_fields:
        assert field in data, f"Missing field: {field}"


@pytest.mark.asyncio
async def test_initiate_order_id_matches_transaction_id(
    async_client: AsyncClient, db_session: AsyncSession
):
    user, _, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 200
    assert res.json()["order_id"] == str(tx.id)


@pytest.mark.asyncio
async def test_initiate_amount_and_currency_from_stored_transaction(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Amount and currency must come from the stored transaction, not from the client."""
    user, _, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 200
    data = res.json()
    assert data["amount"] == f"{tx.amount:.2f}"
    assert data["currency"] == tx.currency


@pytest.mark.asyncio
async def test_initiate_hash_is_correct(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Hash in response must match the independently computed PayHere formula."""
    user, _, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 200
    data = res.json()

    expected_hash = _expected_hash(
        MOCK_MERCHANT_ID,
        str(tx.id),
        f"{tx.amount:.2f}",
        tx.currency,
        MOCK_SECRET,
    )
    assert data["hash"] == expected_hash


@pytest.mark.asyncio
async def test_initiate_secret_not_exposed(
    async_client: AsyncClient, db_session: AsyncSession
):
    """PAYHERE_SECRET must never appear anywhere in the response body."""
    user, _, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 200
    assert MOCK_SECRET not in res.text


@pytest.mark.asyncio
async def test_initiate_bill_description_in_items(
    async_client: AsyncClient, db_session: AsyncSession
):
    """items field should contain biller and account number from the bill."""
    user, bill, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 200
    items = res.json()["items"]
    assert bill.biller in items
    assert bill.account_number in items


@pytest.mark.asyncio
async def test_initiate_urls_from_config(
    async_client: AsyncClient, db_session: AsyncSession
):
    user, _, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 200
    data = res.json()
    assert data["notify_url"] == MOCK_NOTIFY_URL
    assert data["return_url"] == MOCK_RETURN_URL
    assert data["cancel_url"] == MOCK_CANCEL_URL


# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_initiate_idempotent_same_pending_transaction(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Calling initiate twice for the same PENDING tx must return the same hash, no side effects."""
    user, _, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res1 = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )
        res2 = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res1.status_code == 200
    assert res2.status_code == 200
    # Hash must be identical (same inputs → same deterministic output)
    assert res1.json()["hash"] == res2.json()["hash"]
    assert res1.json()["order_id"] == res2.json()["order_id"]


@pytest.mark.asyncio
async def test_initiate_does_not_change_transaction_status(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Initiation must not mutate the transaction or bill — provider stays null, status stays PENDING."""
    user, bill, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 200
    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert tx.provider is None
    assert tx.provider_reference is None
    assert bill.status == "UNPAID"


# ---------------------------------------------------------------------------
# Authentication / authorization failures
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_initiate_missing_auth_returns_401(async_client: AsyncClient, db_session: AsyncSession):
    _, _, _, tx = await create_test_data(db_session)

    res = await async_client.post(f"/api/v1/payments/{tx.id}/initiate")
    assert res.status_code == 401


@pytest.mark.asyncio
async def test_initiate_invalid_token_returns_401(async_client: AsyncClient, db_session: AsyncSession):
    _, _, _, tx = await create_test_data(db_session)

    res = await async_client.post(
        f"/api/v1/payments/{tx.id}/initiate",
        headers={"Authorization": "Bearer invalid.jwt.token"},
    )
    assert res.status_code == 401


@pytest.mark.asyncio
async def test_initiate_another_users_transaction_returns_404(
    async_client: AsyncClient, db_session: AsyncSession
):
    """User B trying to initiate User A's transaction must get 404, not 403 (anti-enumeration)."""
    user_a, _, _, tx_a = await create_test_data(db_session)
    user_b, _, _, _ = await create_test_data(db_session)

    token_b = create_access_token(subject=user_b.id)
    headers_b = {"Authorization": f"Bearer {token_b}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx_a.id}/initiate", headers=headers_b
        )

    assert res.status_code == 404


@pytest.mark.asyncio
async def test_initiate_nonexistent_transaction_returns_404(
    async_client: AsyncClient, db_session: AsyncSession
):
    user, _, _, _ = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    random_tx_id = uuid4()
    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{random_tx_id}/initiate", headers=headers
        )

    assert res.status_code == 404


# ---------------------------------------------------------------------------
# Transaction state guard
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_initiate_success_transaction_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    user, _, _, tx = await create_test_data(db_session, tx_status="SUCCESS")
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 400
    assert "SUCCESS" in res.json()["detail"]


@pytest.mark.asyncio
async def test_initiate_failed_transaction_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    user, _, _, tx = await create_test_data(db_session, tx_status="FAILED")
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 400
    assert "FAILED" in res.json()["detail"]


@pytest.mark.asyncio
async def test_initiate_cancelled_transaction_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    user, _, _, tx = await create_test_data(db_session, tx_status="CANCELLED")
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 400


# ---------------------------------------------------------------------------
# Customer data validation
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_initiate_missing_phone_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    """User with no phone number must get a clear 400 — no fake phone invented."""
    user, _, _, tx = await create_test_data(db_session, phone=None)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 400
    assert "phone" in res.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Missing PayHere configuration
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_initiate_missing_payhere_config_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    """If required PayHere settings are absent, initiation must fail with 400."""
    user, _, _, tx = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    incomplete_settings = _mock_settings()
    incomplete_settings.PAYHERE_MERCHANT_ID = None  # simulate missing credential

    with patch("app.services.payhere.settings", incomplete_settings):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate", headers=headers
        )

    assert res.status_code == 400
    assert "PAYHERE_MERCHANT_ID" in res.json()["detail"]


# ---------------------------------------------------------------------------
# Prepare endpoint regression
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_prepare_endpoint_unchanged(
    async_client: AsyncClient, db_session: AsyncSession
):
    """/payments/prepare must continue to work correctly after Milestone 2 changes."""
    user, bill, pm, _ = await create_test_data(db_session)
    token = create_access_token(subject=user.id)
    headers = {"Authorization": f"Bearer {token}"}

    res = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers,
        json={
            "bill_id": str(bill.id),
            "payment_method_id": str(pm.id),
            "idempotency_key": f"idem_{uuid4()}",
        },
    )

    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "PENDING"
    assert "transaction_id" in data
