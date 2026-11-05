from fastapi import APIRouter, Depends
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.bill import BillResponse
from app.services.billing import BillingService

router = APIRouter()

@router.get("/{biller}/{account_number}", response_model=BillResponse)
async def get_bill_by_account(
    biller: str,
    account_number: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Look up a bill by biller and account number."""
    service = BillingService(db)
    bill = await service.get_bill_by_biller_and_account(biller, account_number, current_user.id)
    return BillResponse.model_validate(bill)

@router.get("/{bill_id}", response_model=BillResponse)
async def get_bill_by_id(
    bill_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Look up a bill by its UUID."""
    service = BillingService(db)
    bill = await service.get_user_bill_by_id(bill_id, current_user.id)
    return BillResponse.model_validate(bill)
