import logging
import urllib.parse
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.schemas.payhere import PayHereCallbackPayload
from app.services.payhere import PayHereService
from app.services.payment import PaymentService

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/callback")
async def payhere_callback(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Public server-to-server callback endpoint invoked by PayHere upon payment completion.

    Requirements:
    1. Public endpoint (no JWT authentication).
    2. Accepts only application/x-www-form-urlencoded data, matching PayHere's contract.
    3. Signature verification FIRST before any database lookup or write.
       If invalid -> return 400.
    4. Transaction lookup with SELECT FOR UPDATE row locking:
       - Unknown or malformed order_id -> return 200 OK (anti-enumeration / prevents infinite retries).
       - Already terminal (SUCCESS / FAILED / CANCELLED) -> return 200 OK (idempotent duplicate handling).
    5. Secondary validation (merchant_id, amount, currency) -> returns 400 on mismatch.
    6. Atomic update of transaction and bill in the same DB transaction on SUCCESS.
    """
    content_type = request.headers.get("content-type", "")
    if "application/x-www-form-urlencoded" not in content_type:
        logger.warning(
            "PayHere callback received with invalid Content-Type: %s. Expected application/x-www-form-urlencoded",
            content_type,
        )
        raise HTTPException(
            status_code=400,
            detail="Invalid Content-Type: expected application/x-www-form-urlencoded",
        )

    raw_body = await request.body()
    parsed = urllib.parse.parse_qs(
        raw_body.decode("utf-8", errors="replace"), keep_blank_values=True
    )
    data = {k: v[0] if len(v) == 1 else v for k, v in parsed.items()}

    try:
        payload = PayHereCallbackPayload.model_validate(data)
    except ValidationError as e:
        logger.warning("PayHere callback payload missing required fields: %s", e)
        raise HTTPException(
            status_code=400,
            detail=f"Missing or invalid required callback fields: {e.errors()}",
        )

    # 2. Signature verification FIRST (before any DB query/write)
    payhere_svc = PayHereService()
    is_valid_sig = payhere_svc.verify_callback_signature(
        merchant_id=payload.merchant_id,
        order_id=payload.order_id,
        payhere_amount=payload.payhere_amount,
        payhere_currency=payload.payhere_currency,
        status_code=payload.status_code,
        md5sig=payload.md5sig,
    )
    if not is_valid_sig:
        logger.warning(
            "PayHere callback signature verification failed for order_id: %s",
            payload.order_id,
        )
        raise HTTPException(status_code=400, detail="Invalid callback signature")

    # 3. Process callback with locking and atomic state updates
    service = PaymentService(db)
    result = await service.process_payhere_callback(payload)
    return result
