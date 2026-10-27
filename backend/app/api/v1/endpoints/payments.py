from fastapi import APIRouter, Depends
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.transaction import PaymentPrepareRequest, PaymentPrepareResponse, TransactionResponse
from app.schemas.payhere import PayHereInitiateResponse
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

@router.post("/{transaction_id}/initiate", response_model=PayHereInitiateResponse)
async def initiate_payment(
    transaction_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Generate signed PayHere checkout parameters for a PENDING transaction.

    The authenticated user must own the transaction. No user_id is accepted
    from the request body, path, or query — identity comes exclusively from the JWT.

    The returned hash is computed server-side using PAYHERE_SECRET which is
    never included in the response.

    Safe to call multiple times for the same PENDING transaction (idempotent).
    """
    service = PaymentService(db)
    return await service.initiate_payment(transaction_id, current_user.id, current_user)

@router.post("/{transaction_id}/reconcile", response_model=TransactionResponse)
async def reconcile_payment(
    transaction_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Safely reconcile a PENDING transaction against the PayHere Merchant Retrieval API.

    The authenticated user must own the transaction. No user_id is accepted
    from the request body, path, or query — identity comes exclusively from the JWT.
    """
    service = PaymentService(db)
    return await service.reconcile_pending_transaction(transaction_id, current_user.id)

@router.get("/{transaction_id}", response_model=TransactionResponse)
async def get_transaction(
    transaction_id: UUID, 
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get details of a specific transaction."""
    service = PaymentService(db)
    return await service.get_transaction(transaction_id, current_user.id)
