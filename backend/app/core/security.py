import jwt
from uuid import UUID
from datetime import datetime, timezone, timedelta
from typing import Optional, Any
from pwdlib import PasswordHash
from pwdlib.hashers.bcrypt import BcryptHasher

from app.core.config import settings

# Initialize modern password hasher with bcrypt
password_hash_helper = PasswordHash((BcryptHasher(),))


def _get_jwt_secret() -> str:
    secret = settings.JWT_SECRET
    if not secret or not secret.strip():
        raise ValueError(
            "JWT_SECRET environment variable is not set. "
            "A secure JWT_SECRET must be configured in your environment or .env file."
        )
    return secret


def get_password_hash(password: str) -> str:
    """Hash a plaintext password using bcrypt. Rejects input > 72 bytes."""
    if len(password.encode("utf-8")) > 72:
        raise ValueError("Password must not exceed 72 bytes for bcrypt.")
    return password_hash_helper.hash(password)


def verify_password(plain_password: str, password_hash: str) -> bool:
    """Verify a plaintext password against its bcrypt hash. Fails if > 72 bytes."""
    if len(plain_password.encode("utf-8")) > 72:
        return False
    return password_hash_helper.verify(plain_password, password_hash)


def create_access_token(
    subject: str | UUID,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """
    Generate an access token with subject, issued-at, expiration, and access type.
    """
    secret = _get_jwt_secret()
    now = datetime.now(timezone.utc)
    if expires_delta is not None:
        expire = now + expires_delta
    else:
        expire = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    payload = {
        "sub": str(subject),
        "iat": int(now.timestamp()),
        "exp": int(expire.timestamp()),
        "type": "access",
    }
    return jwt.encode(payload, secret, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> dict[str, Any]:
    """
    Decode and validate an access token.
    Raises jwt.ExpiredSignatureError if expired,
    jwt.InvalidTokenError if signature or format is invalid.
    """
    secret = _get_jwt_secret()
    payload = jwt.decode(
        token,
        secret,
        algorithms=[settings.JWT_ALGORITHM],
        options={"require": ["sub", "exp", "iat", "type"]},
    )
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("Invalid token type")
    return payload
