from fastapi import APIRouter, Depends
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.transaction import PaymentPrepareRequest, PaymentPrepareResponse, TransactionResponse
from app.services.payment import PaymentService

router = APIRouter()

@router.post("/prepare", response_model=PaymentPrepareResponse)
async def prepare_payment(
    request: PaymentPrepareRequest, 
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Prepare a payment transaction idempotently."""
    service = PaymentService(db)
    return await service.prepare_payment(request, current_user.id)

@router.get("/{transaction_id}", response_model=TransactionResponse)
async def get_transaction(
    transaction_id: UUID, 
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get details of a specific transaction."""
    service = PaymentService(db)
    return await service.get_transaction(transaction_id, current_user.id)
