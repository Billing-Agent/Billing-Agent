from fastapi import APIRouter, Depends
from typing import List
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User

from app.schemas.bill import BillResponse
from app.schemas.payment_method import PaymentMethodResponse
from app.schemas.transaction import TransactionResponse

from app.services.billing import BillingService
from app.services.payment import PaymentService

router = APIRouter()

@router.get("/bills", response_model=List[BillResponse])
async def get_my_bills(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get all bills for the authenticated user."""
    service = BillingService(db)
    bills = await service.get_user_bills(current_user.id)
    return [BillResponse.model_validate(bill) for bill in bills]

@router.get("/payment-methods", response_model=List[PaymentMethodResponse])
async def get_my_payment_methods(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get payment methods for the authenticated user."""
    service = PaymentService(db)
    methods = await service.get_user_payment_methods(current_user.id)
    return [PaymentMethodResponse.model_validate(pm) for pm in methods]

@router.get("/transactions", response_model=List[TransactionResponse])
async def get_my_transactions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get transactions for the authenticated user."""
    service = PaymentService(db)
    transactions = await service.get_user_transactions(current_user.id)

    billing_service = BillingService(db)
    responses = []

    for tx in transactions:
        response = TransactionResponse.model_validate(tx)

        if tx.bill_id:
            bill = await billing_service.get_bill_by_id(tx.bill_id)
            if bill:
                response.biller = bill.biller

        responses.append(response)

    return responses