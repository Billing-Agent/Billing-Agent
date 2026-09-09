from fastapi import APIRouter, Depends, Header
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.schemas.transaction import PaymentPrepareRequest, PaymentPrepareResponse, TransactionResponse
from app.services.payment import PaymentService

router = APIRouter()

# For Phase 3, we mock authentication by passing user_id in the header
# In a real system, this would come from a JWT or session
async def get_current_user_id(x_user_id: UUID = Header(...)) -> UUID:
    return x_user_id

@router.post("/prepare", response_model=PaymentPrepareResponse)
async def prepare_payment(
    request: PaymentPrepareRequest, 
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Prepare a payment transaction idempotently."""
    service = PaymentService(db)
    return await service.prepare_payment(request, user_id)

@router.get("/{transaction_id}", response_model=TransactionResponse)
async def get_transaction(
    transaction_id: UUID, 
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Get details of a specific transaction."""
    service = PaymentService(db)
    return await service.get_transaction(transaction_id, user_id)
