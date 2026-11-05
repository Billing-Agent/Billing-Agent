"""
API tests for POST /api/v1/payhere/callback — Milestone 3.

Tests verify:
- Public endpoint (no JWT required)
- Acceptance of application/x-www-form-urlencoded
- Signature verification FIRST (invalid signature -> 400, no DB modifications)
- Safe handling of unknown and malformed order_ids (returns 200)
- SELECT FOR UPDATE row locking & idempotency on terminal states
- Secondary validations (merchant_id, amount, currency) -> 400 on mismatch
- Status mapping:
    2  -> SUCCESS (tx.status=SUCCESS, provider=PAYHERE, provider_ref=payment_id, bill=PAID, amount_due=0)
    -2 -> FAILED (tx.status=FAILED, provider=PAYHERE, bill untouched)
    -3 -> FAILED (tx.status=FAILED, provider=PAYHERE, bill untouched)
    -1 -> CANCELLED (tx.status=CANCELLED, provider=PAYHERE, bill untouched)
    0  -> PENDING (tx.status=PENDING, provider=PAYHERE, bill untouched)
- Duplicate callbacks are idempotent (returns 200, no re-mutation)
- Dev simulate-success still functions correctly
"""
import hashlib
from decimal import Decimal
from unittest.mock import patch
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.main import app, get_application
from app.core.config import settings
from app.models.bill import Bill
from app.models.payment_method import PaymentMethod
from app.models.transaction import Transaction
from app.models.user import User

# ---------------------------------------------------------------------------
# Test Credentials
# ---------------------------------------------------------------------------
TEST_MERCHANT_ID = "1211111"
TEST_SECRET = "test_merchant_secret_xyz"

PAYHERE_CONFIG = {
    "PAYHERE_MERCHANT_ID": TEST_MERCHANT_ID,
    "PAYHERE_SECRET": TEST_SECRET,
    "PAYHERE_NOTIFY_URL": "http://test/api/v1/payhere/callback",
}


def _md5_upper(v: str) -> str:
    return hashlib.md5(v.encode("utf-8")).hexdigest().upper()


def compute_callback_sig(
    merchant_id: str,
    order_id: str,
    payhere_amount: str,
    payhere_currency: str,
    status_code: str,
    secret: str = TEST_SECRET,
) -> str:
    """Official PayHere callback md5sig formula."""
    hashed_secret = _md5_upper(secret)
    data = (
        merchant_id
        + order_id
        + payhere_amount
        + payhere_currency
        + status_code
        + hashed_secret
    )
    return _md5_upper(data)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        yield ac
    app.dependency_overrides.clear()


_SENTINEL = object()


async def create_test_data(
    db_session: AsyncSession,
    *,
    amount: Decimal = Decimal("250.00"),
    currency: str = "LKR",
    bill_status: str = "UNPAID",
    tx_status: str = "PENDING",
):
    """Create user → bill → payment_method → transaction."""
    user = User(
        name="Sunil Perera",
        email=f"sunil_{uuid4()}@example.com",
        phone=f"+9477{uuid4().int % 10000000:07d}",
        password_hash="hash",
        is_active=True,
    )
    db_session.add(user)
    await db_session.flush()

    bill = Bill(
        user_id=user.id,
        biller="CEB",
        account_number="ACC-12345",
        amount_due=amount,
        currency=currency,
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
        amount=amount,
        currency=currency,
        status=tx_status,
        idempotency_key=f"idem_{uuid4()}",
    )
    db_session.add(tx)
    await db_session.flush()

    return user, bill, pm, tx


# ---------------------------------------------------------------------------
# Test Cases
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_signed_callback_succeeds_with_simulator_disabled(db_session: AsyncSession):
    _, bill, _, tx = await create_test_data(db_session)
    amount = f"{tx.amount:.2f}"
    callback_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": str(tx.id),
        "payhere_amount": amount,
        "payhere_currency": tx.currency,
        "status_code": "2",
        "md5sig": compute_callback_sig(TEST_MERCHANT_ID, str(tx.id), amount, tx.currency, "2"),
        "payment_id": "PH-NO-SIMULATOR",
    }

    with patch.object(settings, "ENABLE_DEV_PAYMENT_SIMULATOR", False):
        protected_app = get_application()
    assert not any(path.startswith("/api/v1/dev/") for path in protected_app.openapi()["paths"])

    async def override_get_db():
        yield db_session

    protected_app.dependency_overrides[get_db] = override_get_db
    try:
        async with AsyncClient(transport=ASGITransport(app=protected_app), base_url="http://test") as client:
            with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
                response = await client.post("/api/v1/payhere/callback", data=callback_data)
                invalid_data = dict(callback_data, md5sig="invalid")
                invalid_response = await client.post("/api/v1/payhere/callback", data=invalid_data)
    finally:
        protected_app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["transaction_status"] == "SUCCESS"
    assert invalid_response.status_code == 400
    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.provider == "PAYHERE"
    assert tx.status == "SUCCESS"
    assert bill.status == "PAID"


@pytest.mark.asyncio
async def test_callback_success_updates_tx_and_bill(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    Verified status_code=2:
    - transaction.status = SUCCESS
    - transaction.provider = PAYHERE
    - transaction.provider_reference = payment_id
    - bill.status = PAID
    - bill.amount_due = 0.00
    """
    _, bill, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    status_code = "2"
    payment_id = "PH-SUCCESS-999"

    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, status_code
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": status_code,
        "md5sig": sig,
        "payment_id": payment_id,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post(
            "/api/v1/payhere/callback",
            data=form_data,
        )

    assert response.status_code == 200
    res_data = response.json()
    assert res_data["status"] == "success"
    assert res_data["transaction_status"] == "SUCCESS"

    # Reload from DB
    await db_session.refresh(tx)
    await db_session.refresh(bill)

    assert tx.status == "SUCCESS"
    assert tx.provider == "PAYHERE"
    assert tx.provider_reference == payment_id
    assert bill.status == "PAID"
    assert bill.amount_due == Decimal("0.00")


@pytest.mark.asyncio
async def test_callback_duplicate_success_is_idempotent(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    Subsequent callbacks for an already-terminal transaction must return 200
    without error and without duplicate mutations.
    """
    _, bill, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, "2"
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": "2",
        "md5sig": sig,
        "payment_id": "PH-FIRST-CALL",
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        # First call -> success
        resp1 = await async_client.post("/api/v1/payhere/callback", data=form_data)
        assert resp1.status_code == 200

        # Duplicate call with a different payment_id to verify no state override
        duplicate_data = dict(form_data)
        duplicate_data["payment_id"] = "PH-SECOND-CALL"
        resp2 = await async_client.post("/api/v1/payhere/callback", data=duplicate_data)
        assert resp2.status_code == 200
        assert resp2.json()["status"] == "already_processed"

    await db_session.refresh(tx)
    await db_session.refresh(bill)

    # Provider reference should still be from the FIRST call
    assert tx.status == "SUCCESS"
    assert tx.provider_reference == "PH-FIRST-CALL"
    assert bill.status == "PAID"


@pytest.mark.asyncio
async def test_callback_failed_status_2(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    status_code = -2 (FAILED):
    - transaction.status = FAILED
    - transaction.provider = PAYHERE
    - bill remains UNPAID and amount_due untouched
    """
    _, bill, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    status_code = "-2"
    payment_id = "PH-FAIL-2"

    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, status_code
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": status_code,
        "md5sig": sig,
        "payment_id": payment_id,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 200
    assert response.json()["transaction_status"] == "FAILED"

    await db_session.refresh(tx)
    await db_session.refresh(bill)

    assert tx.status == "FAILED"
    assert tx.provider == "PAYHERE"
    assert tx.provider_reference == payment_id
    assert bill.status == "UNPAID"
    assert bill.amount_due == Decimal("250.00")


@pytest.mark.asyncio
async def test_callback_failed_status_3_chargedback(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    status_code = -3 (Chargeback/FAILED):
    - transaction.status = FAILED
    - bill remains UNPAID
    """
    _, bill, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    status_code = "-3"

    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, status_code
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": status_code,
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 200
    assert response.json()["transaction_status"] == "FAILED"

    await db_session.refresh(tx)
    await db_session.refresh(bill)

    assert tx.status == "FAILED"
    assert bill.status == "UNPAID"


@pytest.mark.asyncio
async def test_callback_cancelled(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    status_code = -1 (CANCELLED):
    - transaction.status = CANCELLED
    - transaction.provider = PAYHERE
    - bill remains UNPAID
    """
    _, bill, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    status_code = "-1"

    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, status_code
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": status_code,
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 200
    assert response.json()["transaction_status"] == "CANCELLED"

    await db_session.refresh(tx)
    await db_session.refresh(bill)

    assert tx.status == "CANCELLED"
    assert tx.provider == "PAYHERE"
    assert bill.status == "UNPAID"


@pytest.mark.asyncio
async def test_callback_pending_leaves_tx_non_terminal(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    status_code = 0 (PENDING):
    - transaction.status remains PENDING (not terminal!)
    - transaction.provider = PAYHERE
    - bill remains UNPAID
    - Subsequent SUCCESS callback is accepted and updates to SUCCESS
    """
    _, bill, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"

    # 1. PENDING callback arrives
    sig_pending = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, "0"
    )
    form_pending = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": "0",
        "md5sig": sig_pending,
        "payment_id": "PH-PENDING-001",
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        resp_pending = await async_client.post(
            "/api/v1/payhere/callback", data=form_pending
        )
        assert resp_pending.status_code == 200
        assert resp_pending.json()["status"] == "pending"

        await db_session.refresh(tx)
        assert tx.status == "PENDING"
        assert tx.provider == "PAYHERE"
        assert tx.provider_reference == "PH-PENDING-001"
        assert bill.status == "UNPAID"

        # 2. Later SUCCESS callback arrives for same transaction
        sig_success = compute_callback_sig(
            TEST_MERCHANT_ID, order_id, amount_str, tx.currency, "2"
        )
        form_success = {
            "merchant_id": TEST_MERCHANT_ID,
            "order_id": order_id,
            "payhere_amount": amount_str,
            "payhere_currency": tx.currency,
            "status_code": "2",
            "md5sig": sig_success,
            "payment_id": "PH-FINAL-002",
        }
        resp_success = await async_client.post(
            "/api/v1/payhere/callback", data=form_success
        )
        assert resp_success.status_code == 200
        assert resp_success.json()["transaction_status"] == "SUCCESS"

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "SUCCESS"
    assert tx.provider_reference == "PH-FINAL-002"
    assert bill.status == "PAID"


@pytest.mark.asyncio
async def test_callback_invalid_signature_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Tampered or invalid md5sig must immediately return 400 with no DB modifications."""
    _, bill, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": "2",
        "md5sig": "INVALID_SIGNATURE_TAMPERED",
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 400
    assert "signature" in response.json()["detail"].lower()

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert bill.status == "UNPAID"


@pytest.mark.asyncio
async def test_callback_merchant_id_mismatch_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Callback with wrong merchant_id must fail validation and return 400."""
    _, _, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    wrong_merchant = "9999999"

    # Even if signed with the secret for that wrong merchant:
    sig = compute_callback_sig(
        wrong_merchant, order_id, amount_str, tx.currency, "2"
    )

    form_data = {
        "merchant_id": wrong_merchant,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": "2",
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 400
    assert "merchant_id" in response.json()["detail"]


@pytest.mark.asyncio
async def test_callback_amount_mismatch_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Callback with amount different from transaction amount must return 400."""
    _, _, _, tx = await create_test_data(db_session, amount=Decimal("250.00"))
    order_id = str(tx.id)
    tampered_amount = "10.00"  # Paid less than due

    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, tampered_amount, tx.currency, "2"
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": tampered_amount,
        "payhere_currency": tx.currency,
        "status_code": "2",
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 400
    assert "amount" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_callback_currency_mismatch_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Callback with currency different from transaction currency must return 400."""
    _, _, _, tx = await create_test_data(db_session, currency="LKR")
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    wrong_currency = "USD"

    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, wrong_currency, "2"
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": wrong_currency,
        "status_code": "2",
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 400
    assert "currency" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_callback_unknown_order_id_returns_200(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    Valid signature for non-existent transaction UUID must return 200 OK
    (preventing enumeration or infinite PayHere retries).
    """
    unknown_order_id = str(uuid4())
    sig = compute_callback_sig(
        TEST_MERCHANT_ID, unknown_order_id, "100.00", "LKR", "2"
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": unknown_order_id,
        "payhere_amount": "100.00",
        "payhere_currency": "LKR",
        "status_code": "2",
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 200
    assert response.json()["status"] == "ignored"


@pytest.mark.asyncio
async def test_callback_malformed_order_id_returns_200(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    Malformed order_id string that is not a UUID must be handled safely
    and return 200 OK without crashing.
    """
    malformed_order_id = "not-a-valid-uuid-string"
    sig = compute_callback_sig(
        TEST_MERCHANT_ID, malformed_order_id, "100.00", "LKR", "2"
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": malformed_order_id,
        "payhere_amount": "100.00",
        "payhere_currency": "LKR",
        "status_code": "2",
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 200
    assert response.json()["status"] == "ignored"


@pytest.mark.asyncio
async def test_callback_unknown_status_code_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Unsupported status_code must return 400 and not invent state."""
    _, _, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    unknown_status = "99"

    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, unknown_status
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": unknown_status,
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post("/api/v1/payhere/callback", data=form_data)

    assert response.status_code == 400
    assert "unsupported" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_callback_missing_required_fields_returns_400(
    async_client: AsyncClient, db_session: AsyncSession
):
    """Payload missing required fields (e.g. md5sig or order_id) must return 400."""
    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        # Missing md5sig and order_id
        response = await async_client.post(
            "/api/v1/payhere/callback",
            data={"merchant_id": TEST_MERCHANT_ID},
        )
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_callback_no_jwt_required(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    The callback endpoint must be publicly accessible by PayHere servers without
    any Authorization header or JWT.
    """
    _, _, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, "2"
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": "2",
        "md5sig": sig,
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        # Note: headers has NO Authorization
        response = await async_client.post(
            "/api/v1/payhere/callback",
            data=form_data,
        )

    assert response.status_code == 200


@pytest.mark.asyncio
async def test_callback_rejects_json_payload(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    PayHere callbacks must strictly be application/x-www-form-urlencoded.
    JSON requests must be rejected with 400 and cause no DB modification.
    """
    _, _, _, tx = await create_test_data(db_session)
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, "2"
    )

    json_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": "2",
        "md5sig": sig,
        "payment_id": "PH-JSON-101",
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post(
            "/api/v1/payhere/callback",
            json=json_data,
        )

    assert response.status_code == 400
    assert "application/x-www-form-urlencoded" in response.json()["detail"]
    await db_session.refresh(tx)
    assert tx.status == "PENDING"


@pytest.mark.asyncio
async def test_simulate_success_still_works(
    async_client: AsyncClient, db_session: AsyncSession, dev_simulator_headers
):
    """
    Requirement 11:
    POST /api/v1/dev/payments/{transaction_id}/simulate-success
    must remain preserved and working for development/testing.
    """
    _, bill, _, tx = await create_test_data(db_session)

    response = await async_client.post(
        f"/api/v1/dev/payments/{tx.id}/simulate-success", headers=dev_simulator_headers
    )

    assert response.status_code == 200
    res_data = response.json()
    assert res_data["status"] == "SUCCESS"
    assert res_data["provider"] == "MOCK"

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "SUCCESS"
    assert bill.status == "PAID"
    assert bill.amount_due == Decimal("0.00")


@pytest.mark.asyncio
async def test_terminal_cancelled_tx_ignores_later_success_callback(
    async_client: AsyncClient, db_session: AsyncSession
):
    """
    If a transaction was already marked CANCELLED, a later SUCCESS callback
    must return 200 without altering the CANCELLED status or marking the bill paid.
    """
    _, bill, _, tx = await create_test_data(db_session, tx_status="CANCELLED")
    order_id = str(tx.id)
    amount_str = f"{tx.amount:.2f}"
    sig = compute_callback_sig(
        TEST_MERCHANT_ID, order_id, amount_str, tx.currency, "2"
    )

    form_data = {
        "merchant_id": TEST_MERCHANT_ID,
        "order_id": order_id,
        "payhere_amount": amount_str,
        "payhere_currency": tx.currency,
        "status_code": "2",
        "md5sig": sig,
        "payment_id": "PH-LATE-SUCCESS",
    }

    with patch.multiple("app.core.config.settings", **PAYHERE_CONFIG):
        response = await async_client.post(
            "/api/v1/payhere/callback",
            data=form_data,
        )

    assert response.status_code == 200
    assert response.json()["status"] == "already_processed"

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "CANCELLED"
    assert bill.status == "UNPAID"

