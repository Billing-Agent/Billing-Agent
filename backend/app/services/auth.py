from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.repositories.user import UserRepository
from app.schemas.auth import RegisterRequest, LoginRequest, TokenResponse
from app.core.security import get_password_hash, verify_password, create_access_token
from app.core.exceptions import BusinessLogicError


class AuthService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.user_repo = UserRepository(db)

    async def register_user(self, req: RegisterRequest) -> User:
        """
        Registers a new user with a hashed password.
        Raises BusinessLogicError if email is already taken.
        """
        existing_user = await self.user_repo.get_by_email(req.email)
        if existing_user:
            raise BusinessLogicError("Email is already registered.")

        hashed_password = get_password_hash(req.password)
        new_user = User(
            name=req.name,
            email=req.email,
            phone=req.phone,
            password_hash=hashed_password,
            is_active=True,
        )

        self.db.add(new_user)
        await self.db.commit()
        await self.db.refresh(new_user)
        return new_user

    async def authenticate_user(self, req: LoginRequest) -> Optional[User]:
        """
        Verifies credentials against the database.
        Returns User if valid, None otherwise.
        """
        user = await self.user_repo.get_by_email(req.email)
        if not user or not user.password_hash:
            return None

        if not verify_password(req.password, user.password_hash):
            return None

        return user

    def create_user_token(self, user: User) -> TokenResponse:
        """
        Issues a JWT access token for an authenticated user.
        """
        token = create_access_token(subject=str(user.id))
        return TokenResponse(access_token=token, token_type="bearer")
