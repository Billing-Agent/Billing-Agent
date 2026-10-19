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

@pytest.mark.asyncio
async def test_login_user_success(async_client: AsyncClient, db_session: AsyncSession):
    # Setup test user
    from app.core.security import get_password_hash, decode_access_token
    email = f"test_{uuid4()}@example.com"
    password = "CorrectHorseBatteryStaple123!"
    hashed_password = get_password_hash(password)
    
    user = User(
        name="Login Test User",
        email=email,
        password_hash=hashed_password,
        phone="+94770000000",
        is_active=True
    )
    db_session.add(user)
    await db_session.commit()
    
    payload = {
        "email": email,
        "password": password
    }
    
    res = await async_client.post("/api/v1/auth/login", json=payload)
    
    # 1. Successful login returns 200.
    assert res.status_code == 200
    
    data = res.json()
    # 2. Successful login returns access_token.
    assert "access_token" in data
    # 3. token_type is "bearer".
    assert data["token_type"] == "bearer"
    
    # 4. Returned token can be decoded using the existing decode_access_token().
    decoded = decode_access_token(data["access_token"])
    assert decoded["sub"] == str(user.id)
    assert decoded["type"] == "access"

@pytest.mark.asyncio
async def test_login_invalid_password(async_client: AsyncClient, db_session: AsyncSession):
    from app.core.security import get_password_hash
    email = f"test_{uuid4()}@example.com"
    user = User(
        name="Login Test User",
        email=email,
        password_hash=get_password_hash("CorrectPassword!"),
        is_active=True
    )
    db_session.add(user)
    await db_session.commit()
    
    payload = {
        "email": email,
        "password": "WrongPassword!"
    }
    
    res = await async_client.post("/api/v1/auth/login", json=payload)
    # 5. Invalid password returns 401.
    assert res.status_code == 401
    assert "invalid email or password" in res.json()["detail"].lower()

@pytest.mark.asyncio
async def test_login_non_existent_email(async_client: AsyncClient):
    payload = {
        "email": f"nonexistent_{uuid4()}@example.com",
        "password": "SomePassword123!"
    }
    
    res = await async_client.post("/api/v1/auth/login", json=payload)
    # 6. Non-existent email returns 401.
    assert res.status_code == 401
    assert "invalid email or password" in res.json()["detail"].lower()

@pytest.mark.asyncio
async def test_login_inactive_user(async_client: AsyncClient, db_session: AsyncSession):
    from app.core.security import get_password_hash
    email = f"test_{uuid4()}@example.com"
    password = "CorrectPassword!"
    user = User(
        name="Login Test User",
        email=email,
        password_hash=get_password_hash(password),
        is_active=False
    )
    db_session.add(user)
    await db_session.commit()
    
    payload = {
        "email": email,
        "password": password
    }
    
    res = await async_client.post("/api/v1/auth/login", json=payload)
    # 7. Inactive user returns 401.
    assert res.status_code == 401
    assert "invalid email or password" in res.json()["detail"].lower()

@pytest.mark.asyncio
async def test_login_invalid_email_format(async_client: AsyncClient):
    payload = {
        "email": "not-an-email",
        "password": "Password123!"
    }
    
    res = await async_client.post("/api/v1/auth/login", json=payload)
    # 8. Invalid email format returns 422.
    assert res.status_code == 422

@pytest.mark.asyncio
async def test_login_missing_fields(async_client: AsyncClient):
    # 9. Missing password/email returns 422.
    res1 = await async_client.post("/api/v1/auth/login", json={"email": f"test_{uuid4()}@example.com"})
    assert res1.status_code == 422
    
    res2 = await async_client.post("/api/v1/auth/login", json={"password": "Password123!"})
    assert res2.status_code == 422

@pytest.mark.asyncio
async def test_get_current_user_success(async_client: AsyncClient, db_session: AsyncSession):
    from app.core.security import get_password_hash, create_access_token
    email = f"test_{uuid4()}@example.com"
    user = User(
        name="Me Test User",
        email=email,
        password_hash=get_password_hash("CorrectPassword!"),
        is_active=True
    )
    db_session.add(user)
    await db_session.commit()
    
    token = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}
    
    res = await async_client.get("/api/v1/auth/me", headers=headers)
    assert res.status_code == 200
    
    data = res.json()
    assert data["id"] == str(user.id)
    assert data["email"] == email
    assert data["name"] == "Me Test User"
    assert "password" not in data
    assert "password_hash" not in data

@pytest.mark.asyncio
async def test_get_current_user_unauthorized(async_client: AsyncClient):
    res = await async_client.get("/api/v1/auth/me")
    assert res.status_code == 401

@pytest.mark.asyncio
async def test_get_current_user_invalid_token(async_client: AsyncClient):
    headers = {"Authorization": "Bearer invalid_token"}
    res = await async_client.get("/api/v1/auth/me", headers=headers)
    assert res.status_code == 401
    assert "validate credentials" in res.json()["detail"].lower()

@pytest.mark.asyncio
async def test_get_current_user_inactive(async_client: AsyncClient, db_session: AsyncSession):
    from app.core.security import get_password_hash, create_access_token
    user = User(
        name="Inactive Me",
        email=f"test_{uuid4()}@example.com",
        password_hash=get_password_hash("CorrectPassword!"),
        is_active=False
    )
    db_session.add(user)
    await db_session.commit()
    
    token = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}
    
    res = await async_client.get("/api/v1/auth/me", headers=headers)
    assert res.status_code == 401
    assert "inactive" in res.json()["detail"].lower()
