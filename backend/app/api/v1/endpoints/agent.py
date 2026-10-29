"""
Agent chat endpoints.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import EntityNotFoundError, BusinessLogicError
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.agent import (
    AgentChatRequest,
    AgentChatResponse,
    PaymentConfirmRequest,
    PaymentConfirmResponse,
)
from app.schemas.transaction import PaymentPrepareRequest
from app.agent.context import BillingAgentContext
from app.agent.billing_agent import BillingAgent
from app.agent.payment_confirmation import confirmation_store
from app.repositories.bill import BillRepository
from app.repositories.payment_method import PaymentMethodRepository
from app.services.billing import BillingService
from app.services.payment import PaymentService

router = APIRouter()


@router.post("/chat", response_model=AgentChatResponse)
async def chat_with_billing_agent(
    request: AgentChatRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Interact with the conversational Billing Agent.
    - User authentication is strictly enforced via JWT.
    - No user_id is accepted from the client.
    - The agent operates in a strictly read-only mode scoped to current_user.id.
    """
    billing_service = BillingService(db)
    context = BillingAgentContext(
        authenticated_user_id=current_user.id,
        db=db,
        billing_service=billing_service,
    )
    agent = BillingAgent(context=context)
    return await agent.chat(request.message)


@router.post("/payments/confirm", response_model=PaymentConfirmResponse)
async def confirm_payment_plan(
    request: PaymentConfirmRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Confirm a previously generated payment plan and enter the payment preparation pipeline.

    Strict Security & Verification Rules (Phase 8C):
    1. Authenticate user via JWT (current_user.id).
    2. Load confirmation object by confirmation_id.
    3. Verify ownership (confirmation.user_id == current_user.id).
    4. Verify confirmation has not expired.
    5. Verify confirmation has not already been consumed.
    6. Re-load current bill from DB.
    7. Verify bill still belongs to authenticated user.
    8. Verify bill status is still UNPAID.
    9. Verify current bill amount_due matches confirmation.amount.
    10. Verify current bill currency matches confirmation.currency.
    11. Resolve user's single eligible payment method deterministically.
    12. Use server-controlled idempotency key.
    13. Call existing PaymentService.prepare_payment().
    14. Mark confirmation consumed ONLY after prepare succeeds.
    15. Return transaction/preparation result.
    """
    # 1 & 2. Load confirmation
    conf = confirmation_store.get(request.confirmation_id.strip())
    if not conf:
        raise EntityNotFoundError("Payment confirmation not found.")

    # 3. Verify ownership
    if conf.user_id != current_user.id:
        raise EntityNotFoundError("Payment confirmation not found.")

    # 4. Verify not expired
    if conf.is_expired():
        raise BusinessLogicError(
            "This payment confirmation has expired. Please create a new payment request."
        )

    # 5. Verify not consumed
    if conf.consumed:
        raise BusinessLogicError("This payment confirmation has already been used.")

    # 6 & 7. Re-load current bill from DB & verify ownership
    bill_repo = BillRepository(db)
    bill = await bill_repo.get_by_user(conf.bill_id, current_user.id)
    if not bill:
        raise EntityNotFoundError("Bill not found or does not belong to user.")

    # 8. Verify bill status is still UNPAID
    if bill.status != "UNPAID":
        raise BusinessLogicError(f"Cannot pay bill in status: {bill.status}")

    # 9. Verify amount has not changed
    if f"{bill.amount_due:.2f}" != conf.amount:
        raise BusinessLogicError(
            "Bill amount has changed since confirmation was issued. Please create a new payment request."
        )

    # 10. Verify currency has not changed
    if bill.currency != conf.currency:
        raise BusinessLogicError(
            "Bill currency has changed since confirmation was issued. Please create a new payment request."
        )

    # 11. Resolve payment method deterministically
    pm_repo = PaymentMethodRepository(db)
    pms = await pm_repo.get_all_by_user(current_user.id)
    if not pms:
        raise BusinessLogicError(
            "No payment method registered. Please add a payment method before confirming payment."
        )
    if len(pms) > 1:
        raise BusinessLogicError(
            "Multiple payment methods found. Explicit payment method selection is required."
        )
    pm = pms[0]

    # 12 & 13. Call PaymentService.prepare_payment with server-controlled idempotency key
    payment_service = PaymentService(db)
    prepare_req = PaymentPrepareRequest(
        bill_id=conf.bill_id,
        payment_method_id=pm.id,
        idempotency_key=conf.idempotency_key,
    )
    result = await payment_service.prepare_payment(prepare_req, current_user.id)

    # 14. Mark confirmation consumed ONLY after prepare succeeds
    confirmation_store.mark_consumed(conf.confirmation_id)

    # 15. Return preparation result
    return PaymentConfirmResponse(
        transaction_id=result.transaction_id,
        bill_id=result.bill_id,
        amount=result.amount,
        currency=result.currency,
        status=result.status,
    )
