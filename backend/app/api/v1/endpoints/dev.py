import hmac

from fastapi import APIRouter, Depends, Header, HTTPException
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.config import settings
from app.db.session import get_db
from app.schemas.transaction import TransactionResponse
from app.services.payment import PaymentService

router = APIRouter()

def require_simulator_token(x_dev_simulator_token: str | None = Header(default=None)) -> None:
    configured_token = settings.DEV_PAYMENT_SIMULATOR_TOKEN
    if (
        not configured_token
        or not x_dev_simulator_token
        or not hmac.compare_digest(
            x_dev_simulator_token.encode("utf-8"),
            configured_token.get_secret_value().encode("utf-8"),
        )
    ):
        raise HTTPException(status_code=404, detail="Not Found")

@router.post(
    "/payments/{transaction_id}/simulate-success",
    response_model=TransactionResponse,
    dependencies=[Depends(require_simulator_token)],
)
async def simulate_success(transaction_id: UUID, db: AsyncSession = Depends(get_db)):
    """
    DEVELOPMENT ONLY endpoint to simulate a successful payment.
    Atomically updates the transaction and bill statuses.
    """
    service = PaymentService(db)
    return await service.simulate_success(transaction_id)
