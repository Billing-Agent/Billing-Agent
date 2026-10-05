import pytest
from httpx import AsyncClient
from uuid import uuid4
from app.models.user import User
from app.models.payment_method import PaymentMethod
from app.models.bill import Bill
from sqlalchemy.ext.asyncio import AsyncSession
import pytest_asyncio
from app.main import app
from app.db.session import get_db
from httpx import ASGITransport
from app.core.security import create_access_token

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()

async def setup_test_users(db_session: AsyncSession):
    user1_id = uuid4()
    user2_id = uuid4()
    
    user1 = User(id=user1_id, name="Test User 1", email=f"test1_{user1_id}@example.com", password_hash="hash", is_active=True)
    user2 = User(id=user2_id, name="Test User 2", email=f"test2_{user2_id}@example.com", password_hash="hash", is_active=True)
    
    db_session.add_all([user1, user2])
    await db_session.flush()
    return user1, user2

@pytest.mark.asyncio
async def test_get_user_payment_methods_authenticated_own(async_client: AsyncClient, db_session: AsyncSession):
    user1, _ = await setup_test_users(db_session)

    pm1 = PaymentMethod(user_id=user1.id, provider="Sandbox", token_reference="tok1", is_default=True)
    pm2 = PaymentMethod(user_id=user1.id, provider="Sandbox", token_reference="tok2", is_default=False)
    db_session.add_all([pm1, pm2])
    await db_session.flush()

    token = create_access_token(subject=user1.id)
    headers = {"Authorization": f"Bearer {token}"}

    response = await async_client.get(f"/api/v1/users/{user1.id}/payment-methods", headers=headers)
    
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    assert data[0]["provider"] == "Sandbox"


@pytest.mark.asyncio
async def test_get_user_payment_methods_authenticated_other(async_client: AsyncClient, db_session: AsyncSession):
    user1, user2 = await setup_test_users(db_session)

    # user1 tries to access user2's payment methods
    token = create_access_token(subject=user1.id)
    headers = {"Authorization": f"Bearer {token}"}

    response = await async_client.get(f"/api/v1/users/{user2.id}/payment-methods", headers=headers)
    
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_get_user_bills_authenticated_own(async_client: AsyncClient, db_session: AsyncSession):
    user1, _ = await setup_test_users(db_session)

    from decimal import Decimal
    bill1 = Bill(user_id=user1.id, biller="Water", account_number="123", amount_due=Decimal("50.00"), status="UNPAID")
    db_session.add(bill1)
    await db_session.flush()

    token = create_access_token(subject=user1.id)
    headers = {"Authorization": f"Bearer {token}"}

    response = await async_client.get(f"/api/v1/users/{user1.id}/bills", headers=headers)
    
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["biller"] == "Water"


@pytest.mark.asyncio
async def test_get_user_bills_authenticated_other(async_client: AsyncClient, db_session: AsyncSession):
    user1, user2 = await setup_test_users(db_session)

    # user1 tries to access user2's bills
    token = create_access_token(subject=user1.id)
    headers = {"Authorization": f"Bearer {token}"}

    response = await async_client.get(f"/api/v1/users/{user2.id}/bills", headers=headers)
    
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_get_user_bills_missing_auth(async_client: AsyncClient, db_session: AsyncSession):
    user1, _ = await setup_test_users(db_session)

    # No Authorization header
    response = await async_client.get(f"/api/v1/users/{user1.id}/bills")
    
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_get_user_bills_invalid_auth(async_client: AsyncClient, db_session: AsyncSession):
    user1, _ = await setup_test_users(db_session)

    # Invalid token
    headers = {"Authorization": "Bearer invalidtoken"}
    response = await async_client.get(f"/api/v1/users/{user1.id}/bills", headers=headers)
    
    assert response.status_code == 401
