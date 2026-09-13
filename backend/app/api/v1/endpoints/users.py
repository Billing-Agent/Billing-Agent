from fastapi import APIRouter, Depends
from uuid import UUID
from typing import List
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.schemas.bill import BillResponse
from app.services.billing import BillingService

router = APIRouter()

@router.get("/{user_id}/bills", response_model=List[BillResponse])
async def get_user_bills(user_id: UUID, db: AsyncSession = Depends(get_db)):
    """Development endpoint to get all bills for a given user."""
    service = BillingService(db)
    bills = await service.get_user_bills(user_id)
    return [BillResponse.model_validate(bill) for bill in bills]

from app.schemas.payment_method import PaymentMethodResponse
from app.services.payment import PaymentService

@router.get("/{user_id}/payment-methods", response_model=List[PaymentMethodResponse])
async def get_user_payment_methods(user_id: UUID, db: AsyncSession = Depends(get_db)):
    """Development ONLY endpoint to get payment methods for a given user."""
    service = PaymentService(db)
    methods = await service.get_user_payment_methods(user_id)
    return [PaymentMethodResponse.model_validate(pm) for pm in methods]
