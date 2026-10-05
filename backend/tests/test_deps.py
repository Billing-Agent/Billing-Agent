import pytest
import jwt
from uuid import uuid4
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.security import create_access_token
from app.models.user import User

@pytest.mark.asyncio
async def test_get_current_user_valid_token(db_session):
    # Setup test user
    user_id = uuid4()
    user = User(
        id=user_id,
        name="Test User",
        email=f"test_{user_id}@example.com",
        password_hash="fakehash",
        phone="+94770000000",
        is_active=True
    )
    db_session.add(user)
    await db_session.commit()

    token = create_access_token(subject=user_id)
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    current_user = await get_current_user(token=credentials, db=db_session)
    
    assert current_user is not None
    assert current_user.id == user_id
    assert current_user.email == user.email


@pytest.mark.asyncio
async def test_get_current_user_invalid_token(db_session):
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials="invalid.token.string")

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(token=credentials, db=db_session)
    
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Could not validate credentials"


@pytest.mark.asyncio
async def test_get_current_user_missing_sub(db_session):
    # Create a valid JWT but without a 'sub' claim
    payload = {
        "exp": 9999999999,
        "iat": 1000000000,
        "type": "access",
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(token=credentials, db=db_session)
    
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Could not validate credentials"


@pytest.mark.asyncio
async def test_get_current_user_invalid_sub_uuid(db_session):
    # Create a valid JWT but with an invalid UUID 'sub' claim
    payload = {
        "sub": "not-a-uuid",
        "exp": 9999999999,
        "iat": 1000000000,
        "type": "access",
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(token=credentials, db=db_session)
    
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Could not validate credentials"


@pytest.mark.asyncio
async def test_get_current_user_not_found(db_session):
    # Valid token but user does not exist in the DB
    user_id = uuid4()
    token = create_access_token(subject=user_id)
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(token=credentials, db=db_session)
    
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "User not found"


@pytest.mark.asyncio
async def test_get_current_user_inactive(db_session):
    # Setup test user as inactive
    user_id = uuid4()
    user = User(
        id=user_id,
        name="Inactive User",
        email=f"inactive_{user_id}@example.com",
        password_hash="fakehash",
        phone="+94770000000",
        is_active=False
    )
    db_session.add(user)
    await db_session.commit()

    token = create_access_token(subject=user_id)
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(token=credentials, db=db_session)
    
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Inactive user"

@pytest.mark.asyncio
async def test_get_current_user_missing_token(db_session):
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(token=None, db=db_session)
    
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Not authenticated"
