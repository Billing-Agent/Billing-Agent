import pytest
from httpx import AsyncClient
from uuid import uuid4
from app.models.user import User
from app.models.payment_method import PaymentMethod
from sqlalchemy.ext.asyncio import AsyncSession
import pytest_asyncio
from app.main import app
from app.db.session import get_db
from httpx import ASGITransport

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()

@pytest.mark.asyncio
async def test_get_user_payment_methods(async_client: AsyncClient, db_session: AsyncSession):
    # Setup test user and payment methods
    user = User(name="Test User", email=f"test_{uuid4()}@example.com")
    db_session.add(user)
    await db_session.flush()

    pm1 = PaymentMethod(user_id=user.id, provider="Sandbox", token_reference="tok1", is_default=True)
    pm2 = PaymentMethod(user_id=user.id, provider="Sandbox", token_reference="tok2", is_default=False)
    db_session.add_all([pm1, pm2])
    await db_session.flush()

    # Call endpoint
    response = await async_client.get(f"/api/v1/users/{user.id}/payment-methods")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    assert data[0]["provider"] == "Sandbox"
    
    # Cleanup is handled by rollback fixtures typically, but manual rollback if needed.
