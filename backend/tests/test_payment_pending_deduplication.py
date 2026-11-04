"""
Tests for duplicate/stale PENDING payment attempt prevention and safety guards.

Coverage:
1. Existing PENDING transaction reuse (same user, same bill).
2. Different idempotency keys on same bill returns existing PENDING without duplicates.
3. Concurrent prepare requests with different idempotency keys creates exactly one PENDING transaction.
4. Different bills can each have their own PENDING transaction.
5. Different users: strict isolation, no cross-user reuse or leakage.
6. Bill already PAID: prepare_payment rejects new transaction creation.
7. Initiate old PENDING transaction after bill becomes PAID: rejected with 400, PayHere service not called.
8. Initiate PENDING transaction while bill is UNPAID: succeeds.
9. Duplicate success handling in callback on already PAID bill.
10. Duplicate success handling in reconciliation on already PAID bill.
"""
import pytest
import asyncio
from decimal import Decimal
from uuid import uuid4
from unittest.mock import patch, MagicMock, AsyncMock
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.db.session import get_db, AsyncSessionLocal
from app.models.user import User
from app.models.bill import Bill
from app.models.payment_method import PaymentMethod
from app.models.transaction import Transaction
from app.core.security import create_access_token
from app.schemas.payhere import PayHereCallbackPayload, PayHerePaymentRetrievalResult
from app.services.payment import PaymentService
from sqlalchemy import select, func
import pytest_asyncio


@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


def _mock_settings():
    m = MagicMock()
    m.PAYHERE_MERCHANT_ID = "SANDBOX_MERCHANT_123"
    m.PAYHERE_SECRET = "SANDBOX_SECRET_xyz"
    m.PAYHERE_NOTIFY_URL = "https://example.com/api/v1/payhere/callback"
    m.PAYHERE_RETURN_URL = "billingagent://payment/return"
    m.PAYHERE_CANCEL_URL = "billingagent://payment/cancel"
    m.PAYHERE_DEFAULT_ADDRESS = "No. 1 Main Street"
    m.PAYHERE_DEFAULT_CITY = "Colombo"
    m.PAYHERE_DEFAULT_COUNTRY = "Sri Lanka"
    return m


@pytest.mark.asyncio
async def test_prepare_payment_reuses_existing_pending_transaction(async_client, db_session):
    """
    1. Existing PENDING transaction reuse
    - same user, same bill
    - second prepare request returns existing transaction
    - transaction count unchanged
    """
    user = User(name="Alice Pending", email=f"alice_pending_{uuid4()}@test.com", is_active=True)
    db_session.add(user)
    await db_session.flush()

    token = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    bill = Bill(user_id=user.id, biller="CEB", account_number=f"ACC_{uuid4().hex[:6]}", amount_due=Decimal("5000.00"), status="UNPAID")
    pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill, pm])
    await db_session.flush()

    # First prepare request creates a PENDING transaction
    key1 = f"idem_{uuid4()}"
    res1 = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers,
        json={
            "bill_id": str(bill.id),
            "payment_method_id": str(pm.id),
            "idempotency_key": key1,
        },
    )
    assert res1.status_code == 200
    tx1_id = res1.json()["transaction_id"]
    assert res1.json()["status"] == "PENDING"

    # Verify 1 transaction exists in DB
    tx_count_res = await db_session.execute(
        select(func.count(Transaction.id)).filter(Transaction.bill_id == bill.id)
    )
    assert tx_count_res.scalar() == 1

    # Second prepare request with the SAME idempotency key returns existing transaction
    res2 = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers,
        json={
            "bill_id": str(bill.id),
            "payment_method_id": str(pm.id),
            "idempotency_key": key1,
        },
    )
    assert res2.status_code == 200
    assert res2.json()["transaction_id"] == tx1_id

    # Verify transaction count is still 1
    tx_count_res2 = await db_session.execute(
        select(func.count(Transaction.id)).filter(Transaction.bill_id == bill.id)
    )
    assert tx_count_res2.scalar() == 1


@pytest.mark.asyncio
async def test_prepare_payment_different_idempotency_key_returns_existing_pending(async_client, db_session):
    """
    2. Different idempotency key but same bill
    - still returns existing PENDING
    - does not create duplicate
    """
    user = User(name="Bob Pending", email=f"bob_pending_{uuid4()}@test.com", is_active=True)
    db_session.add(user)
    await db_session.flush()

    token = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    bill = Bill(user_id=user.id, biller="Water Board", account_number=f"WB_{uuid4().hex[:6]}", amount_due=Decimal("1500.00"), status="UNPAID")
    pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill, pm])
    await db_session.flush()

    key1 = f"idem_key1_{uuid4()}"
    res1 = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers,
        json={
            "bill_id": str(bill.id),
            "payment_method_id": str(pm.id),
            "idempotency_key": key1,
        },
    )
    assert res1.status_code == 200
    tx1_id = res1.json()["transaction_id"]

    # Now request prepare with a DIFFERENT idempotency key for the same bill
    key2 = f"idem_key2_{uuid4()}"
    res2 = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers,
        json={
            "bill_id": str(bill.id),
            "payment_method_id": str(pm.id),
            "idempotency_key": key2,
        },
    )
    assert res2.status_code == 200
    assert res2.json()["transaction_id"] == tx1_id
    assert res2.json()["status"] == "PENDING"

    # Transaction count remains 1
    tx_count_res = await db_session.execute(
        select(func.count(Transaction.id)).filter(Transaction.bill_id == bill.id)
    )
    assert tx_count_res.scalar() == 1


@pytest.mark.asyncio
async def test_prepare_payment_different_bills_have_independent_pending(async_client, db_session):
    """
    4. Different bills
    - can each have their own PENDING transaction
    """
    user = User(name="Charlie Pending", email=f"charlie_{uuid4()}@test.com", is_active=True)
    db_session.add(user)
    await db_session.flush()

    token = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    bill_a = Bill(user_id=user.id, biller="CEB", account_number=f"CEB_{uuid4().hex[:6]}", amount_due=Decimal("2000.00"), status="UNPAID")
    bill_b = Bill(user_id=user.id, biller="SLT", account_number=f"SLT_{uuid4().hex[:6]}", amount_due=Decimal("3500.00"), status="UNPAID")
    pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill_a, bill_b, pm])
    await db_session.flush()

    res_a = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers,
        json={
            "bill_id": str(bill_a.id),
            "payment_method_id": str(pm.id),
            "idempotency_key": f"idem_a_{uuid4()}",
        },
    )
    assert res_a.status_code == 200
    tx_a_id = res_a.json()["transaction_id"]

    res_b = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers,
        json={
            "bill_id": str(bill_b.id),
            "payment_method_id": str(pm.id),
            "idempotency_key": f"idem_b_{uuid4()}",
        },
    )
    assert res_b.status_code == 200
    tx_b_id = res_b.json()["transaction_id"]

    assert tx_a_id != tx_b_id


@pytest.mark.asyncio
async def test_prepare_payment_user_isolation(async_client, db_session):
    """
    5. Different users
    - no cross-user reuse/leakage
    """
    user_a = User(name="User A", email=f"user_a_{uuid4()}@test.com", is_active=True)
    user_b = User(name="User B", email=f"user_b_{uuid4()}@test.com", is_active=True)
    db_session.add_all([user_a, user_b])
    await db_session.flush()

    token_a = create_access_token(subject=str(user_a.id))
    headers_a = {"Authorization": f"Bearer {token_a}"}
    token_b = create_access_token(subject=str(user_b.id))
    headers_b = {"Authorization": f"Bearer {token_b}"}

    bill_a = Bill(user_id=user_a.id, biller="CEB", account_number=f"A_{uuid4().hex[:6]}", amount_due=Decimal("1000.00"), status="UNPAID")
    pm_a = PaymentMethod(user_id=user_a.id, provider="Test", token_reference="tok_a", is_default=True)
    bill_b = Bill(user_id=user_b.id, biller="CEB", account_number=f"B_{uuid4().hex[:6]}", amount_due=Decimal("1000.00"), status="UNPAID")
    pm_b = PaymentMethod(user_id=user_b.id, provider="Test", token_reference="tok_b", is_default=True)
    db_session.add_all([bill_a, pm_a, bill_b, pm_b])
    await db_session.flush()

    # User A prepares payment
    res_a = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers_a,
        json={
            "bill_id": str(bill_a.id),
            "payment_method_id": str(pm_a.id),
            "idempotency_key": f"idem_a_{uuid4()}",
        },
    )
    assert res_a.status_code == 200

    # User B attempting to prepare payment for User A's bill gets 404
    res_b_on_a = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers_b,
        json={
            "bill_id": str(bill_a.id),
            "payment_method_id": str(pm_b.id),
            "idempotency_key": f"idem_b_{uuid4()}",
        },
    )
    assert res_b_on_a.status_code == 404


@pytest.mark.asyncio
async def test_prepare_payment_rejects_already_paid_bill(async_client, db_session):
    """
    6. Bill already PAID
    - prepare_payment rejects new transaction creation
    """
    user = User(name="David Paid", email=f"david_{uuid4()}@test.com", is_active=True)
    db_session.add(user)
    await db_session.flush()

    token = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    bill = Bill(user_id=user.id, biller="CEB", account_number=f"PAID_{uuid4().hex[:6]}", amount_due=Decimal("0.00"), status="PAID")
    pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill, pm])
    await db_session.flush()

    res = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers,
        json={
            "bill_id": str(bill.id),
            "payment_method_id": str(pm.id),
            "idempotency_key": f"idem_paid_{uuid4()}",
        },
    )
    assert res.status_code == 400
    assert "Cannot pay bill in status: PAID" in res.json()["detail"]


@pytest.mark.asyncio
async def test_initiate_old_pending_transaction_after_bill_is_paid_rejected(async_client, db_session):
    """
    7. Initiate old PENDING transaction after bill becomes PAID
    - rejected
    - PayHere initiation service NOT called
    - Transaction remains PENDING (not mutated)
    - Bill remains PAID (not mutated)
    """
    user = User(name="Eve Initiate", email=f"eve_{uuid4()}@test.com", phone="+94771234567", is_active=True)
    db_session.add(user)
    await db_session.flush()

    token = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    # Bill is already settled/PAID
    bill = Bill(user_id=user.id, biller="CEB", account_number=f"SETTLED_{uuid4().hex[:6]}", amount_due=Decimal("0.00"), status="PAID")
    pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill, pm])
    await db_session.flush()

    # Old transaction that was previously left PENDING
    old_tx = Transaction(
        user_id=user.id,
        bill_id=bill.id,
        payment_method_id=pm.id,
        amount=Decimal("5000.00"),
        currency="LKR",
        status="PENDING",
        idempotency_key=f"idem_old_{uuid4()}",
    )
    db_session.add(old_tx)
    await db_session.flush()

    with patch("app.services.payhere.PayHereService.build_initiate_params") as mock_build_params:
        res = await async_client.post(
            f"/api/v1/payments/{old_tx.id}/initiate",
            headers=headers,
        )
        # Service must NOT be called
        mock_build_params.assert_not_called()

    assert res.status_code == 400
    assert res.json()["detail"] == "This bill has already been paid. This payment attempt can no longer be initiated."

    # Verify old transaction remains PENDING and bill remains PAID
    await db_session.refresh(old_tx)
    await db_session.refresh(bill)
    assert old_tx.status == "PENDING"
    assert bill.status == "PAID"


@pytest.mark.asyncio
async def test_initiate_pending_transaction_while_bill_unpaid_succeeds(async_client, db_session):
    """
    8. Existing PENDING + bill still UNPAID
    - initiation still allowed
    """
    user = User(name="Frank Unpaid", email=f"frank_{uuid4()}@test.com", phone="+94779876543", is_active=True)
    db_session.add(user)
    await db_session.flush()

    token = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    bill = Bill(user_id=user.id, biller="CEB", account_number=f"UNP_{uuid4().hex[:6]}", amount_due=Decimal("4200.00"), status="UNPAID")
    pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill, pm])
    await db_session.flush()

    tx = Transaction(
        user_id=user.id,
        bill_id=bill.id,
        payment_method_id=pm.id,
        amount=bill.amount_due,
        currency="LKR",
        status="PENDING",
        idempotency_key=f"idem_frank_{uuid4()}",
    )
    db_session.add(tx)
    await db_session.flush()

    with patch("app.services.payhere.settings", _mock_settings()):
        res = await async_client.post(
            f"/api/v1/payments/{tx.id}/initiate",
            headers=headers,
        )

    assert res.status_code == 200
    assert res.json()["order_id"] == str(tx.id)
    assert res.json()["amount"] == "4200.00"


@pytest.mark.asyncio
async def test_concurrency_prepare_different_idempotency_keys():
    """
    3. Same bill, concurrent/near-concurrent prepare behavior
    - verify only one PENDING transaction exists even when concurrent requests have different idempotency keys
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        async with AsyncSessionLocal() as session:
            user = User(name="Conc Test", email=f"conc_{uuid4()}@test.com", is_active=True)
            session.add(user)
            await session.commit()

            bill = Bill(user_id=user.id, biller="CEB", account_number=f"CONC_{uuid4().hex[:6]}", amount_due=Decimal("3000.00"), status="UNPAID")
            pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
            session.add_all([bill, pm])
            await session.commit()
            bill_id = bill.id
            pm_id = pm.id

        token = create_access_token(subject=str(user.id))
        headers = {"Authorization": f"Bearer {token}"}

        # Fire 5 concurrent prepare requests with DIFFERENT idempotency keys
        reqs = [
            ac.post(
                "/api/v1/payments/prepare",
                headers=headers,
                json={
                    "bill_id": str(bill_id),
                    "payment_method_id": str(pm_id),
                    "idempotency_key": f"conc_key_{i}_{uuid4()}",
                },
            )
            for i in range(5)
        ]
        responses = await asyncio.gather(*reqs)

        # All requests must succeed (200 OK)
        assert all(r.status_code == 200 for r in responses)

        # All requests must return the exact same transaction ID
        tx_ids = set(r.json()["transaction_id"] for r in responses)
        assert len(tx_ids) == 1

        # Check DB to confirm exactly 1 transaction was created
        async with AsyncSessionLocal() as session:
            tx_count_res = await session.execute(
                select(func.count(Transaction.id)).filter(Transaction.bill_id == bill_id)
            )
            assert tx_count_res.scalar() == 1


@pytest.mark.asyncio
async def test_duplicate_success_callback_on_already_paid_bill(async_client, db_session, caplog):
    """
    Duplicate SUCCESS safety (callback):
    - bill is already PAID
    - another transaction for same bill receives provider SUCCESS
    - preserves provider SUCCESS on that transaction
    - does NOT re-apply bill settlement logic
    - logs warning
    """
    user = User(name="Grace Dup", email=f"grace_{uuid4()}@test.com", is_active=True)
    db_session.add(user)
    await db_session.flush()

    bill = Bill(user_id=user.id, biller="CEB", account_number=f"DUP_{uuid4().hex[:6]}", amount_due=Decimal("0.00"), status="PAID")
    pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill, pm])
    await db_session.flush()

    tx = Transaction(
        user_id=user.id,
        bill_id=bill.id,
        payment_method_id=pm.id,
        amount=Decimal("5000.00"),
        currency="LKR",
        status="PENDING",
        idempotency_key=f"idem_dup_{uuid4()}",
    )
    db_session.add(tx)
    await db_session.flush()

    service = PaymentService(db_session)
    payload = PayHereCallbackPayload(
        merchant_id="SANDBOX_MERCHANT_123",
        order_id=str(tx.id),
        payment_id="320011122233",
        payhere_amount="5000.00",
        payhere_currency="LKR",
        status_code="2",
        md5sig="ignored_by_mock",
    )

    with patch("app.services.payhere.PayHereService.validate_callback_fields"), \
         caplog.at_level("WARNING"):
        result = await service.process_payhere_callback(payload)

    assert result["status"] == "success"
    await db_session.refresh(tx)
    await db_session.refresh(bill)

    # Provider SUCCESS is preserved
    assert tx.status == "SUCCESS"
    assert tx.provider == "PAYHERE"
    assert tx.provider_reference == "320011122233"

    # Bill remains PAID without re-settlement
    assert bill.status == "PAID"
    assert bill.amount_due == Decimal("0.00")

    # Warning logged
    assert any("Duplicate payment detected for bill" in record.message for record in caplog.records)


@pytest.mark.asyncio
async def test_duplicate_success_reconciliation_on_already_paid_bill(async_client, db_session, caplog):
    """
    Duplicate SUCCESS safety (reconciliation):
    - bill is already PAID
    - another transaction receives provider SUCCESS via retrieval client
    - preserves provider SUCCESS on that transaction
    - does NOT re-apply bill settlement logic
    - logs warning
    """
    user = User(name="Helen Reconcile", email=f"helen_{uuid4()}@test.com", is_active=True)
    db_session.add(user)
    await db_session.flush()

    bill = Bill(user_id=user.id, biller="CEB", account_number=f"REC_{uuid4().hex[:6]}", amount_due=Decimal("0.00"), status="PAID")
    pm = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill, pm])
    await db_session.flush()

    tx = Transaction(
        user_id=user.id,
        bill_id=bill.id,
        payment_method_id=pm.id,
        amount=Decimal("7200.00"),
        currency="LKR",
        status="PENDING",
        idempotency_key=f"idem_rec_{uuid4()}",
    )
    db_session.add(tx)
    await db_session.flush()

    mock_client = AsyncMock()
    mock_client.retrieve_payment.return_value = PayHerePaymentRetrievalResult(
        order_id=str(tx.id),
        status="SUCCESS",
        amount=Decimal("7200.00"),
        currency="LKR",
        provider_reference="320099988877",
    )

    service = PaymentService(db_session)
    with caplog.at_level("WARNING"):
        res = await service.reconcile_pending_transaction(
            tx_id=tx.id,
            user_id=user.id,
            retrieval_client=mock_client,
        )

    assert res.status == "SUCCESS"
    assert res.provider == "PAYHERE"
    assert res.provider_reference == "320099988877"

    await db_session.refresh(bill)
    assert bill.status == "PAID"
    assert bill.amount_due == Decimal("0.00")

    assert any("Duplicate payment detected for bill" in record.message for record in caplog.records)
