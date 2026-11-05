import pytest
import asyncio
import os
from httpx import AsyncClient, ASGITransport
from uuid import uuid4
from decimal import Decimal
from unittest.mock import patch

from app.main import app, get_application
from app.db.session import get_db
from app.core.config import Settings, settings
from app.models.user import User
from app.models.bill import Bill
from app.models.payment_method import PaymentMethod
from app.models.transaction import Transaction
from app.core.security import create_access_token
from sqlalchemy import select
from sqlalchemy.engine import make_url

import pytest_asyncio

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            yield ac
    finally:
        app.dependency_overrides.clear()

@pytest.mark.asyncio
async def test_api_payments_prepare(async_client, db_session):
    user_a = User(name="User A", email="pay_a@test.com", is_active=True)
    user_b = User(name="User B", email="pay_b@test.com", is_active=True)
    db_session.add_all([user_a, user_b])
    await db_session.flush()

    token_a = create_access_token(subject=str(user_a.id))
    headers_a = {"Authorization": f"Bearer {token_a}"}

    bill_a = Bill(user_id=user_a.id, biller="CEB", account_number="A1", amount_due=Decimal("100"), status="UNPAID")
    bill_paid = Bill(user_id=user_a.id, biller="CEB", account_number="A2", amount_due=Decimal("0"), status="PAID")
    bill_b = Bill(user_id=user_b.id, biller="CEB", account_number="B1", amount_due=Decimal("100"), status="UNPAID")
    db_session.add_all([bill_a, bill_paid, bill_b])
    await db_session.flush()

    pm_a = PaymentMethod(user_id=user_a.id, provider="Test", token_reference="tok", is_default=True)
    pm_b = PaymentMethod(user_id=user_b.id, provider="Test", token_reference="tok2", is_default=True)
    db_session.add_all([pm_a, pm_b])
    await db_session.flush()

    # Test missing auth
    idem_key = f"idem_{uuid4()}"
    res_no_auth = await async_client.post(
        "/api/v1/payments/prepare",
        json={
            "bill_id": str(bill_a.id),
            "payment_method_id": str(pm_a.id),
            "idempotency_key": idem_key
        }
    )
    assert res_no_auth.status_code == 401

    # Test invalid auth
    res_invalid_auth = await async_client.post(
        "/api/v1/payments/prepare",
        headers={"Authorization": "Bearer invalid_token"},
        json={
            "bill_id": str(bill_a.id),
            "payment_method_id": str(pm_a.id),
            "idempotency_key": idem_key
        }
    )
    assert res_invalid_auth.status_code == 401

    # 9. Payment preparation creates PENDING transaction
    res_success = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers_a,
        json={
            "bill_id": str(bill_a.id),
            "payment_method_id": str(pm_a.id),
            "idempotency_key": idem_key
        }
    )
    assert res_success.status_code == 200
    assert res_success.json()["status"] == "PENDING"
    tx_id = res_success.json()["transaction_id"]

    # 13. Duplicate idempotency key does not create duplicate transactions
    res_dup = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers_a,
        json={
            "bill_id": str(bill_a.id),
            "payment_method_id": str(pm_a.id),
            "idempotency_key": idem_key
        }
    )
    assert res_dup.status_code == 200
    assert res_dup.json()["transaction_id"] == tx_id # Same tx returned

    # 10. Payment preparation rejects a bill belonging to another user
    res_wrong_bill = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers_a,
        json={
            "bill_id": str(bill_b.id),
            "payment_method_id": str(pm_a.id),
            "idempotency_key": f"idem_{uuid4()}"
        }
    )
    assert res_wrong_bill.status_code == 404

    # 11. Payment preparation rejects a payment method belonging to another user
    res_wrong_pm = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers_a,
        json={
            "bill_id": str(bill_a.id),
            "payment_method_id": str(pm_b.id),
            "idempotency_key": f"idem_{uuid4()}"
        }
    )
    assert res_wrong_pm.status_code == 404

    # 12. Payment preparation rejects an already PAID bill
    res_paid = await async_client.post(
        "/api/v1/payments/prepare",
        headers=headers_a,
        json={
            "bill_id": str(bill_paid.id),
            "payment_method_id": str(pm_a.id),
            "idempotency_key": f"idem_{uuid4()}"
        }
    )
    assert res_paid.status_code == 400

@pytest.mark.asyncio
async def test_api_payments_get_transaction(async_client, db_session):
    user_a = User(name="User A", email="pay_get_a@test.com", is_active=True)
    user_b = User(name="User B", email="pay_get_b@test.com", is_active=True)
    db_session.add_all([user_a, user_b])
    await db_session.flush()

    token_a = create_access_token(subject=str(user_a.id))
    token_b = create_access_token(subject=str(user_b.id))
    headers_a = {"Authorization": f"Bearer {token_a}"}
    headers_b = {"Authorization": f"Bearer {token_b}"}

    bill_a = Bill(user_id=user_a.id, biller="CEB", account_number="A1", amount_due=Decimal("100"), status="UNPAID")
    db_session.add(bill_a)
    await db_session.flush()

    pm_a = PaymentMethod(user_id=user_a.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add(pm_a)
    await db_session.flush()

    tx_a = Transaction(user_id=user_a.id, bill_id=bill_a.id, payment_method_id=pm_a.id, amount=Decimal("100"), status="PENDING", idempotency_key=f"idem_{uuid4()}")
    db_session.add(tx_a)
    await db_session.flush()

    # 7. GET /payments/{transaction_id} succeeds for the owner
    res_owner = await async_client.get(f"/api/v1/payments/{tx_a.id}", headers=headers_a)
    assert res_owner.status_code == 200
    assert res_owner.json()["id"] == str(tx_a.id)

    # 8. User B cannot retrieve User A's transaction
    res_other = await async_client.get(f"/api/v1/payments/{tx_a.id}", headers=headers_b)
    assert res_other.status_code == 404


@pytest.mark.asyncio
async def test_dev_simulator_route_requires_explicit_isolated_nonproduction_config(db_session):
    with patch.dict(os.environ, {}, clear=True):
        default_settings = Settings(_env_file=None)
    assert default_settings.APP_ENVIRONMENT == "production"
    assert default_settings.ENABLE_DEV_PAYMENT_SIMULATOR is False
    assert default_settings.DEV_PAYMENT_SIMULATOR_TOKEN is None

    user = User(name="Simulator Guard", email=f"sim_guard_{uuid4()}@test.com", is_active=True)
    db_session.add(user)
    await db_session.flush()
    bill = Bill(user_id=user.id, biller="CEB", account_number="SIM-GUARD", amount_due=Decimal("100"), status="UNPAID")
    method = PaymentMethod(user_id=user.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add_all([bill, method])
    await db_session.flush()
    tx = Transaction(user_id=user.id, bill_id=bill.id, payment_method_id=method.id, amount=Decimal("100"), status="PENDING", idempotency_key=f"idem_{uuid4()}")
    db_session.add(tx)
    await db_session.flush()

    test_database_url = settings.DATABASE_URL
    test_token = settings.DEV_PAYMENT_SIMULATOR_TOKEN
    normal_database_url = str(make_url(test_database_url).set(database="billing_agent"))
    cases = [
        (False, "test", test_database_url, test_token),
        (True, "production", test_database_url, test_token),
        (True, "development", normal_database_url, test_token),
        (True, "test", test_database_url, None),
    ]
    path = f"/api/v1/dev/payments/{tx.id}/simulate-success"
    route_pattern = "/api/v1/dev/payments/{transaction_id}/simulate-success"
    headers = {"Authorization": f"Bearer {create_access_token(subject=str(user.id))}"}

    for enabled, environment, database_url, token in cases:
        with patch.object(settings, "ENABLE_DEV_PAYMENT_SIMULATOR", enabled), \
             patch.object(settings, "APP_ENVIRONMENT", environment), \
             patch.object(settings, "DATABASE_URL", database_url), \
             patch.object(settings, "DEV_PAYMENT_SIMULATOR_TOKEN", token):
            protected_app = get_application()

        assert route_pattern not in protected_app.openapi()["paths"]
        async with AsyncClient(transport=ASGITransport(app=protected_app), base_url="http://test") as client:
            response = await client.post(path, headers=headers)
        assert response.status_code == 404

    await db_session.refresh(tx)
    await db_session.refresh(bill)
    assert tx.status == "PENDING"
    assert bill.status == "UNPAID"

    with patch.object(settings, "ENABLE_DEV_PAYMENT_SIMULATOR", True), \
         patch.object(settings, "APP_ENVIRONMENT", "test"), \
         patch.object(settings, "DATABASE_URL", test_database_url):
        isolated_app = get_application()
    assert route_pattern in isolated_app.openapi()["paths"]
    async with AsyncClient(transport=ASGITransport(app=isolated_app), base_url="http://test") as client:
        response = await client.post(path, headers=headers)
    assert response.status_code == 404
    await db_session.refresh(tx)
    assert tx.status == "PENDING"


@pytest.mark.asyncio
async def test_api_payments_simulate_success(async_client, db_session, dev_simulator_headers):
    user_a = User(name="User A", email="pay_sim@test.com", is_active=True)
    db_session.add(user_a)
    await db_session.flush()

    bill_a = Bill(user_id=user_a.id, biller="CEB", account_number="A1", amount_due=Decimal("100"), status="UNPAID")
    db_session.add(bill_a)
    await db_session.flush()

    pm_a = PaymentMethod(user_id=user_a.id, provider="Test", token_reference="tok", is_default=True)
    db_session.add(pm_a)
    await db_session.flush()

    tx_a = Transaction(user_id=user_a.id, bill_id=bill_a.id, payment_method_id=pm_a.id, amount=Decimal("100"), status="PENDING", idempotency_key=f"idem_{uuid4()}")
    db_session.add(tx_a)
    await db_session.flush()

    # 14-17. Simulate success updates transaction and bill
    res_sim = await async_client.post(f"/api/v1/dev/payments/{tx_a.id}/simulate-success", headers=dev_simulator_headers)
    assert res_sim.status_code == 200
    data = res_sim.json()
    assert data["status"] == "SUCCESS"
    assert data["provider"] == "MOCK"
    assert data["provider_reference"] is not None

    # Verify bill is paid
    # Refresh bill in session
    await db_session.refresh(bill_a)
    assert bill_a.status == "PAID"
    assert bill_a.amount_due == Decimal("0.00")

    # 18. Repeating simulated success does not duplicate/process again
    res_sim2 = await async_client.post(f"/api/v1/dev/payments/{tx_a.id}/simulate-success", headers=dev_simulator_headers)
    assert res_sim2.status_code == 200
    assert res_sim2.json()["status"] == "SUCCESS"

@pytest.mark.asyncio
async def test_api_payments_concurrency(committed_concurrency_user_id, dev_simulator_headers):
    # To test true concurrency, we must NOT override the db dependency.
    # The app will use its own engine pool allowing true concurrent DB transactions.
    
    # 1. Setup committed data in the disposable test database.
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        from app.db.session import AsyncSessionLocal
        
        # We need a user, bill, and PM. Let's just create them directly via a one-off session.
        async with AsyncSessionLocal() as session:
            user_c = User(id=committed_concurrency_user_id, name="Concurrency User", email=f"conc_{uuid4()}@test.com", is_active=True)
            session.add(user_c)
            await session.commit()
            
            bill_c = Bill(user_id=user_c.id, biller="CEB", account_number=f"C_{uuid4().hex[:6]}", amount_due=Decimal("500"), status="UNPAID")
            pm_c = PaymentMethod(user_id=user_c.id, provider="Test", token_reference="tok", is_default=True)
            session.add_all([bill_c, pm_c])
            await session.commit()

        token_c = create_access_token(subject=str(user_c.id))
        headers_c = {"Authorization": f"Bearer {token_c}"}

        # CONCURRENCY TEST 1: Duplicate Idempotency Key (prepare)
        idem_key = f"idem_conc_{uuid4()}"
        req_json = {
            "bill_id": str(bill_c.id),
            "payment_method_id": str(pm_c.id),
            "idempotency_key": idem_key
        }
        
        # Fire 5 concurrent prepare requests
        reqs = [
            ac.post("/api/v1/payments/prepare", headers=headers_c, json=req_json)
            for _ in range(5)
        ]
        responses = await asyncio.gather(*reqs)
        
        # All should be 200 (idempotent), and ALL should return the EXACT SAME transaction_id
        assert all(r.status_code == 200 for r in responses)
        tx_ids = set(r.json()["transaction_id"] for r in responses)
        assert len(tx_ids) == 1
        tx_id = tx_ids.pop()

        # CONCURRENCY TEST 2: Simulate Success Race Condition
        # Fire 5 concurrent simulate-success requests
        sim_reqs = [
            ac.post(f"/api/v1/dev/payments/{tx_id}/simulate-success", headers=dev_simulator_headers)
            for _ in range(5)
        ]
        sim_responses = await asyncio.gather(*sim_reqs)
        
        # All should be 200 (idempotent)
        assert all(r.status_code == 200 for r in sim_responses)
        
        # Ensure bill was updated correctly, amount_due = 0 exactly
        async with AsyncSessionLocal() as session:
            from app.repositories.bill import BillRepository
            repo = BillRepository(session)
            final_bill = await repo.get(bill_c.id)
            assert final_bill.status == "PAID"
            assert final_bill.amount_due == Decimal("0.00")
