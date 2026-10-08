import pytest
from httpx import AsyncClient, ASGITransport
from uuid import uuid4
from decimal import Decimal
from app.models.user import User
from app.models.payment_method import PaymentMethod
from app.models.bill import Bill
from app.models.transaction import Transaction
from sqlalchemy.ext.asyncio import AsyncSession
import pytest_asyncio
from app.main import app
from app.db.session import get_db
from app.core.security import create_access_token

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()

async def setup_test_data(db_session: AsyncSession):
    user_a_id = uuid4()
    user_b_id = uuid4()
    
    user_a = User(id=user_a_id, name="User A", email=f"a_{user_a_id}@example.com", password_hash="hash", is_active=True)
    user_b = User(id=user_b_id, name="User B", email=f"b_{user_b_id}@example.com", password_hash="hash", is_active=True)
    
    db_session.add_all([user_a, user_b])
    await db_session.flush()

    bill_a = Bill(user_id=user_a.id, biller="Water", account_number="123", amount_due=Decimal("50.00"), status="UNPAID")
    bill_b = Bill(user_id=user_b.id, biller="Electric", account_number="456", amount_due=Decimal("150.00"), status="UNPAID")
    db_session.add_all([bill_a, bill_b])
    await db_session.flush()

    pm_a = PaymentMethod(user_id=user_a.id, provider="Sandbox", token_reference="tok_a", is_default=True)
    pm_b = PaymentMethod(user_id=user_b.id, provider="Sandbox", token_reference="tok_b", is_default=True)
    db_session.add_all([pm_a, pm_b])
    await db_session.flush()

    tx_a = Transaction(user_id=user_a.id, bill_id=bill_a.id, payment_method_id=pm_a.id, amount=Decimal("50.00"), status="PENDING", idempotency_key=f"idem_{uuid4()}")
    tx_b = Transaction(user_id=user_b.id, bill_id=bill_b.id, payment_method_id=pm_b.id, amount=Decimal("150.00"), status="PENDING", idempotency_key=f"idem_{uuid4()}")
    db_session.add_all([tx_a, tx_b])
    await db_session.flush()

    return user_a, user_b, bill_a, bill_b, pm_a, pm_b, tx_a, tx_b

@pytest.mark.asyncio
async def test_get_me_bills_success(async_client: AsyncClient, db_session: AsyncSession):
    user_a, user_b, bill_a, bill_b, _, _, _, _ = await setup_test_data(db_session)
    token_a = create_access_token(subject=user_a.id)
    headers = {"Authorization": f"Bearer {token_a}"}

    res = await async_client.get("/api/v1/me/bills", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert len(data) == 1
    assert data[0]["id"] == str(bill_a.id)
    assert str(bill_b.id) not in [b["id"] for b in data]

@pytest.mark.asyncio
async def test_get_me_bills_unauthorized(async_client: AsyncClient):
    res_missing = await async_client.get("/api/v1/me/bills")
    assert res_missing.status_code == 401

    res_invalid = await async_client.get("/api/v1/me/bills", headers={"Authorization": "Bearer invalid"})
    assert res_invalid.status_code == 401

@pytest.mark.asyncio
async def test_get_me_payment_methods_success(async_client: AsyncClient, db_session: AsyncSession):
    user_a, user_b, _, _, pm_a, pm_b, _, _ = await setup_test_data(db_session)
    token_a = create_access_token(subject=user_a.id)
    headers = {"Authorization": f"Bearer {token_a}"}

    res = await async_client.get("/api/v1/me/payment-methods", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert len(data) == 1
    assert data[0]["id"] == str(pm_a.id)
    assert "token_reference" not in data[0]
    assert data[0]["provider"] == pm_a.provider
    assert str(pm_b.id) not in [p["id"] for p in data]

@pytest.mark.asyncio
async def test_get_me_payment_methods_unauthorized(async_client: AsyncClient):
    res_missing = await async_client.get("/api/v1/me/payment-methods")
    assert res_missing.status_code == 401

@pytest.mark.asyncio
async def test_get_me_transactions_success(async_client: AsyncClient, db_session: AsyncSession):
    user_a, user_b, _, _, _, _, tx_a, tx_b = await setup_test_data(db_session)
    token_a = create_access_token(subject=user_a.id)
    headers = {"Authorization": f"Bearer {token_a}"}

    res = await async_client.get("/api/v1/me/transactions", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert len(data) == 1
    assert data[0]["id"] == str(tx_a.id)
    assert str(tx_b.id) not in [t["id"] for t in data]

@pytest.mark.asyncio
async def test_get_me_transactions_unauthorized(async_client: AsyncClient):
    res_missing = await async_client.get("/api/v1/me/transactions")
    assert res_missing.status_code == 401
