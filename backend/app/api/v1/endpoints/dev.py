from fastapi import APIRouter, Depends
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.schemas.transaction import TransactionResponse
from app.services.payment import PaymentService

router = APIRouter()

@router.post("/payments/{transaction_id}/simulate-success", response_model=TransactionResponse)
async def simulate_success(transaction_id: UUID, db: AsyncSession = Depends(get_db)):
    """
    DEVELOPMENT ONLY endpoint to simulate a successful payment.
    Atomically updates the transaction and bill statuses.
    """
    service = PaymentService(db)
    return await service.simulate_success(transaction_id)
