import pytest
import jwt
from uuid import uuid4
from datetime import timedelta
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    decode_access_token,
)
from app.schemas.user import UserResponse
from app.schemas.auth import RegisterRequest, LoginRequest
from app.models.user import User
from app.services.auth import AuthService
from app.core.exceptions import BusinessLogicError


def test_password_hashing_not_plaintext():
    plain = "SuperSecret123!"
    hashed = get_password_hash(plain)

    # Must not be equal to plaintext
    assert hashed != plain
    # Must look like a bcrypt hash ($2b$...)
    assert hashed.startswith("$2b$")


def test_password_verification():
    plain = "SuperSecret123!"
    hashed = get_password_hash(plain)

    # Correct password verifies
    assert verify_password(plain, hashed) is True

    # Incorrect password fails
    assert verify_password("WrongPassword!", hashed) is False
    assert verify_password("", hashed) is False


def test_password_boundary_validation():
    from pydantic import ValidationError

    # 1. Minimum length boundary (8 chars)
    # 7 chars fails
    with pytest.raises(ValidationError):
        RegisterRequest(name="A", email="a@b.com", password="a" * 7)

    # 8 chars succeeds
    req_8 = RegisterRequest(name="A", email="a@b.com", password="a" * 8)
    assert req_8.password == "a" * 8

    # 2. Maximum length boundary (72 chars/bytes)
    # 72 chars succeeds
    req_72 = RegisterRequest(name="A", email="a@b.com", password="a" * 72)
    assert req_72.password == "a" * 72

    # 73 chars fails schema validation (no silent truncation)
    with pytest.raises(ValidationError):
        RegisterRequest(name="A", email="a@b.com", password="a" * 73)

    # 3. LoginRequest consistent validation
    # 72 chars succeeds
    login_72 = LoginRequest(email="a@b.com", password="a" * 72)
    assert login_72.password == "a" * 72

    # 73 chars fails schema validation (no silent truncation)
    with pytest.raises(ValidationError):
        LoginRequest(email="a@b.com", password="a" * 73)

    # 4. Multibyte UTF-8 boundary (e.g. 25 emojis of 4 bytes each = 100 bytes > 72 bytes)
    with pytest.raises(ValidationError):
        RegisterRequest(name="A", email="a@b.com", password="🔒" * 20)  # 20 * 4 = 80 bytes > 72 bytes


def test_password_hashing_boundary_and_no_truncation():
    # Exactly 72 bytes hashes and verifies
    pw_72 = "k" * 72
    hashed_72 = get_password_hash(pw_72)
    assert verify_password(pw_72, hashed_72) is True

    # Longer than 72 bytes raises ValueError in get_password_hash rather than silently truncating
    with pytest.raises(ValueError, match="Password must not exceed 72 bytes"):
        get_password_hash("k" * 73)

    # verify_password rejects longer than 72 bytes rather than truncating and matching
    assert verify_password("k" * 73, hashed_72) is False


def test_jwt_generation_and_decoding():
    user_id = uuid4()
    token = create_access_token(subject=user_id)

    # Token can be decoded
    payload = decode_access_token(token)

    # Expected fields and types
    assert payload["sub"] == str(user_id)
    assert payload["type"] == "access"
    assert "exp" in payload
    assert "iat" in payload


def test_jwt_expired_rejected():
    user_id = uuid4()
    # Create token that expired 10 seconds ago
    expired_token = create_access_token(
        subject=user_id,
        expires_delta=timedelta(seconds=-10),
    )

    with pytest.raises(jwt.ExpiredSignatureError):
        decode_access_token(expired_token)


def test_jwt_tampered_rejected():
    user_id = uuid4()
    token = create_access_token(subject=user_id)

    # Tamper with token characters
    parts = token.split(".")
    tampered_payload = parts[1][:-2] + ("aa" if not parts[1].endswith("aa") else "bb")
    tampered_token = f"{parts[0]}.{tampered_payload}.{parts[2]}"

    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(tampered_token)


def test_jwt_invalid_type_rejected():
    from app.core.config import settings
    # Encode token with invalid type
    payload = {
        "sub": str(uuid4()),
        "exp": 9999999999,
        "iat": 1000000000,
        "type": "refresh",
    }
    invalid_type_token = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

    with pytest.raises(jwt.InvalidTokenError, match="Invalid token type"):
        decode_access_token(invalid_type_token)


def test_user_response_never_exposes_password_or_hash():
    from datetime import datetime, timezone
    user = User(
        id=uuid4(),
        name="Security Tester",
        email="security@example.com",
        phone="+94770000000",
        password_hash=get_password_hash("secretpassword"),
        is_active=True,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )

    response = UserResponse.model_validate(user)
    dumped = response.model_dump()

    assert "password" not in dumped
    assert "password_hash" not in dumped
    assert dumped["name"] == "Security Tester"
    assert dumped["email"] == "security@example.com"


@pytest.mark.asyncio
async def test_auth_service_registration_and_authentication(db_session):
    auth_service = AuthService(db_session)
    email = f"authtest_{uuid4()}@example.com"
    password = "CorrectHorseBatteryStaple123"

    # 1. Register User
    reg_req = RegisterRequest(
        name="Auth Test User",
        email=email,
        password=password,
        phone="+94771234567",
    )
    user = await auth_service.register_user(reg_req)

    assert user.id is not None
    assert user.email == email
    assert user.password_hash != password
    assert verify_password(password, user.password_hash) is True
    assert user.is_active is True

    # 2. Duplicate registration fails
    with pytest.raises(BusinessLogicError, match="already registered"):
        await auth_service.register_user(reg_req)

    # 3. Authenticate with correct credentials
    login_req_valid = LoginRequest(email=email, password=password)
    auth_user = await auth_service.authenticate_user(login_req_valid)
    assert auth_user is not None
    assert auth_user.id == user.id

    # 4. Authenticate with wrong password returns None
    login_req_wrong_pw = LoginRequest(email=email, password="WrongPassword!")
    assert await auth_service.authenticate_user(login_req_wrong_pw) is None

    # 5. Authenticate with non-existent email returns None
    login_req_wrong_email = LoginRequest(email="nonexistent@example.com", password=password)
    assert await auth_service.authenticate_user(login_req_wrong_email) is None

    # 6. Generate access token from user
    token_resp = auth_service.create_user_token(user)
    assert token_resp.token_type == "bearer"
    decoded = decode_access_token(token_resp.access_token)
    assert decoded["sub"] == str(user.id)
