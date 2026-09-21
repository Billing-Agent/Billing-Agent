from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.schemas.auth import RegisterRequest
from app.schemas.user import UserResponse
from app.services.auth import AuthService
from app.core.exceptions import BusinessLogicError

router = APIRouter()

@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    req: RegisterRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Register a new user.
    """
    auth_service = AuthService(db)
    try:
        user = await auth_service.register_user(req)
        return UserResponse.model_validate(user)
    except BusinessLogicError as e:
        if "already registered" in str(e).lower() or "already taken" in str(e).lower():
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
