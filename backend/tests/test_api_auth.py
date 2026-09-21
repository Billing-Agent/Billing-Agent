import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession
import pytest_asyncio
from app.main import app
from app.db.session import get_db
from app.models.user import User
from app.core.security import verify_password
from uuid import uuid4

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()

@pytest.mark.asyncio
async def test_register_user_success(async_client: AsyncClient, db_session: AsyncSession):
    email = f"test_{uuid4()}@example.com"
    payload = {
        "name": "Test User",
        "email": email,
        "password": "Password123!",
        "phone": "+94770000000"
    }
    
    res = await async_client.post("/api/v1/auth/register", json=payload)
    assert res.status_code == 201
    
    data = res.json()
    assert data["name"] == "Test User"
    assert data["email"] == email
    assert "password" not in data
    assert "password_hash" not in data
    
    # Verify in DB that it is hashed
    from sqlalchemy import select
    result = await db_session.execute(select(User).where(User.email == email))
    user = result.scalars().first()
    assert user is not None
    assert user.password_hash is not None
    assert user.password_hash != "Password123!"
    assert verify_password("Password123!", user.password_hash) is True

@pytest.mark.asyncio
async def test_register_user_duplicate_email(async_client: AsyncClient):
    email = f"test_{uuid4()}@example.com"
    payload = {
        "name": "Test User",
        "email": email,
        "password": "Password123!",
        "phone": "+94770000000"
    }
    
    res = await async_client.post("/api/v1/auth/register", json=payload)
    assert res.status_code == 201
    
    # Try again
    res2 = await async_client.post("/api/v1/auth/register", json=payload)
    assert res2.status_code == 409
    assert "already registered" in res2.json()["detail"].lower()

@pytest.mark.asyncio
async def test_register_user_invalid_email(async_client: AsyncClient):
    payload = {
        "name": "Test User",
        "email": "not-an-email",
        "password": "Password123!",
        "phone": "+94770000000"
    }
    
    res = await async_client.post("/api/v1/auth/register", json=payload)
    assert res.status_code == 422

@pytest.mark.asyncio
async def test_register_user_password_too_short(async_client: AsyncClient):
    payload = {
        "name": "Test User",
        "email": f"test_{uuid4()}@example.com",
        "password": "short",
        "phone": "+94770000000"
    }
    
    res = await async_client.post("/api/v1/auth/register", json=payload)
    assert res.status_code == 422

@pytest.mark.asyncio
async def test_register_user_password_too_long(async_client: AsyncClient):
    payload = {
        "name": "Test User",
        "email": f"test_{uuid4()}@example.com",
        "password": "a" * 73,
        "phone": "+94770000000"
    }
    
    res = await async_client.post("/api/v1/auth/register", json=payload)
    assert res.status_code == 422
