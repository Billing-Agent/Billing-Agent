import uuid
import logging
from decimal import Decimal
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
import asyncio

from app.models.transaction import Transaction
from app.repositories.transaction import TransactionRepository
from app.repositories.bill import BillRepository
from app.repositories.payment_method import PaymentMethodRepository
from app.core.exceptions import EntityNotFoundError, BusinessLogicError, ConcurrencyConflictError
from app.schemas.transaction import PaymentPrepareRequest, PaymentPrepareResponse, TransactionResponse
from app.schemas.payhere import PayHereInitiateResponse, PayHereCallbackPayload

logger = logging.getLogger(__name__)

class PaymentService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.tx_repo = TransactionRepository(db)
        self.bill_repo = BillRepository(db)
        self.pm_repo = PaymentMethodRepository(db)

    async def get_user_payment_methods(self, user_id: uuid.UUID):
        return await self.pm_repo.get_all_by_user(user_id)

    async def get_user_transactions(self, user_id: uuid.UUID):
        return await self.tx_repo.get_all_by_user(user_id)

    async def initiate_payment(
        self, tx_id: uuid.UUID, user_id: uuid.UUID, user
    ) -> PayHereInitiateResponse:
        """
        Generate signed PayHere checkout parameters for a PENDING transaction.

        Ownership: returns 404 if the transaction does not exist or belongs to
        a different user — intentionally identical error to prevent enumeration.

        State guard: returns 400 via BusinessLogicError if the transaction is
        not PENDING (e.g. already SUCCESS, FAILED, CANCELLED).

        Idempotent: makes no DB writes. Calling this multiple times for the
        same PENDING transaction is safe and returns fresh (but equivalent)
        checkout parameters each time.

        Provider field: intentionally NOT set here. provider is set atomically
        with the status transition in Milestone 3 callback processing, consistent
        with the simulate_success pattern.
        """
        # --- Load and verify ownership (intentional 404 on both not-found and wrong-user) ---
        tx = await self.tx_repo.get_by_user(tx_id, user_id)
        if not tx:
            raise EntityNotFoundError("Transaction not found or does not belong to user.")

        # --- State guard ---
        if tx.status != "PENDING":
            raise BusinessLogicError(
                f"Cannot initiate payment for transaction in status: {tx.status}. "
                "Only PENDING transactions may be initiated."
            )

        # --- Load bill for a meaningful item description ---
        bill_description: str | None = None
        if tx.bill_id:
            bill = await self.bill_repo.get(tx.bill_id)
            if bill:
                bill_description = f"{bill.biller} - Account {bill.account_number}"

        # --- Delegate all PayHere param assembly and signing to PayHereService ---
        from app.services.payhere import PayHereService
        payhere_svc = PayHereService()
        return payhere_svc.build_initiate_params(
            transaction=tx,
            user=user,
            bill_description=bill_description,
        )

    async def process_payhere_callback(self, payload: PayHereCallbackPayload) -> dict:
        """
        Process the server-to-server PayHere payment callback.

        1. Signature verification was already performed before DB access.
        2. Transaction lookup with row lock (SELECT FOR UPDATE).
           - If order_id is invalid UUID or tx is not found -> log and return 200 (anti-enumeration/anti-retry).
           - If tx is already terminal (SUCCESS / FAILED / CANCELLED) -> return 200 (idempotent).
        3. Secondary field validation:
           - merchant_id, amount, currency against transaction and configuration.
           - Raises BusinessLogicError (HTTP 400) on mismatch.
        4. Status mapping:
           - "2"  -> SUCCESS (tx.status="SUCCESS", tx.provider="PAYHERE", tx.provider_reference=payment_id,
                              lock bill, bill.status="PAID", bill.amount_due=Decimal("0.00"),
                              commit tx + bill atomically)
           - "-2" / "-3" -> FAILED (tx.status="FAILED", tx.provider="PAYHERE", tx.provider_reference=payment_id,
                                    bill untouched, commit)
           - "-1" -> CANCELLED (tx.status="CANCELLED", tx.provider="PAYHERE", tx.provider_reference=payment_id,
                                bill untouched, commit)
           - "0"  -> PENDING (tx.status remains "PENDING", tx.provider="PAYHERE",
                              tx.provider_reference=payment_id if supplied, bill untouched, commit)
           - unknown -> BusinessLogicError (HTTP 400), no DB modification.
        """
        # Validate order_id format as UUID
        try:
            tx_id = uuid.UUID(payload.order_id)
        except (ValueError, TypeError, AttributeError):
            logger.warning("PayHere callback received with invalid order_id: %s", payload.order_id)
            return {"status": "ignored", "detail": "Invalid order_id format"}

        # Lock transaction row (SELECT FOR UPDATE)
        tx = await self.tx_repo.get_with_lock(tx_id)
        if not tx:
            logger.warning("PayHere callback received for non-existent transaction: %s", tx_id)
            return {"status": "ignored", "detail": "Transaction not found"}

        # Idempotency: if already terminal, return 200 without re-applying mutations
        if tx.status in ["SUCCESS", "FAILED", "CANCELLED"]:
            logger.info("Transaction %s is already terminal (%s). Duplicate callback ignored.", tx.id, tx.status)
            return {"status": "already_processed", "transaction_status": tx.status}

        # Secondary callback validation (merchant_id, amount, currency)
        from app.services.payhere import PayHereService
        payhere_svc = PayHereService()
        payhere_svc.validate_callback_fields(
            merchant_id=payload.merchant_id,
            payhere_amount=payload.payhere_amount,
            payhere_currency=payload.payhere_currency,
            transaction=tx,
        )

        # Status code mapping
        mapped_status = payhere_svc.map_status_code(payload.status_code)
        if mapped_status is None:
            raise BusinessLogicError(f"Unsupported PayHere status code: {payload.status_code}")

        if mapped_status == "SUCCESS":
            tx.status = "SUCCESS"
            tx.provider = "PAYHERE"
            tx.provider_reference = payload.payment_id

            if tx.bill_id:
                bill = await self.bill_repo.get_with_lock(tx.bill_id)
                if not bill or bill.user_id != tx.user_id:
                    raise BusinessLogicError("Transaction has invalid associated bill.")
                bill.status = "PAID"
                bill.amount_due = Decimal("0.00")

            await self.db.commit()
            await self.db.refresh(tx)
            return {"status": "success", "transaction_id": str(tx.id), "transaction_status": tx.status}

        elif mapped_status in ["FAILED", "CANCELLED"]:
            tx.status = mapped_status
            tx.provider = "PAYHERE"
            if payload.payment_id:
                tx.provider_reference = payload.payment_id

            await self.db.commit()
            await self.db.refresh(tx)
            return {"status": "success", "transaction_id": str(tx.id), "transaction_status": tx.status}

        elif mapped_status == "PENDING":
            # PENDING callback: tx remains PENDING
            tx.provider = "PAYHERE"
            if payload.payment_id:
                tx.provider_reference = payload.payment_id

            await self.db.commit()
            await self.db.refresh(tx)
            return {"status": "pending", "transaction_id": str(tx.id), "transaction_status": tx.status}

    async def prepare_payment(self, req: PaymentPrepareRequest, user_id: uuid.UUID) -> PaymentPrepareResponse:
        # First check idempotency to fail fast if already exists
        existing_tx = await self.tx_repo.get_by_idempotency_key(req.idempotency_key)
        if existing_tx:
            if existing_tx.user_id != user_id:
                raise BusinessLogicError("Idempotency key already used by another user.")
            return self._build_prepare_response(existing_tx)

        # Validate Bill
        bill = await self.bill_repo.get_by_user(req.bill_id, user_id)
        if not bill:
            raise EntityNotFoundError("Bill not found or does not belong to user.")
        if bill.status != "UNPAID":
            raise BusinessLogicError(f"Cannot pay bill in status: {bill.status}")

        # Validate Payment Method
        pm = await self.pm_repo.get_by_user(req.payment_method_id, user_id)
        if not pm:
            raise EntityNotFoundError("Payment method not found or does not belong to user.")

        new_tx = Transaction(
            user_id=user_id,
            bill_id=req.bill_id,
            payment_method_id=req.payment_method_id,
            amount=bill.amount_due,
            currency=bill.currency,
            status="PENDING",
            idempotency_key=req.idempotency_key
        )

        self.db.add(new_tx)

        try:
            await self.db.commit()
            await self.db.refresh(new_tx)
        except IntegrityError:
            # Handle concurrent idempotency conflict
            await self.db.rollback()
            existing_tx = await self.tx_repo.get_by_idempotency_key(req.idempotency_key)
            if existing_tx:
                if existing_tx.user_id != user_id:
                    raise BusinessLogicError("Idempotency key already used by another user.")
                return self._build_prepare_response(existing_tx)
            else:
                raise ConcurrencyConflictError("A concurrency conflict occurred while preparing payment.")

        return self._build_prepare_response(new_tx)

    async def get_transaction(self, tx_id: uuid.UUID, user_id: uuid.UUID) -> TransactionResponse:
        tx = await self.tx_repo.get_by_user(tx_id, user_id)
        if not tx:
            raise EntityNotFoundError("Transaction not found or does not belong to user.")
        return TransactionResponse.model_validate(tx)

    async def simulate_success(self, tx_id: uuid.UUID) -> TransactionResponse:
        # Start a new nested transaction or use the current one
        # Use with_for_update for row-level lock on the transaction to prevent race conditions
        tx = await self.tx_repo.get_with_lock(tx_id)
        if not tx:
            raise EntityNotFoundError("Transaction not found.")

        if tx.status in ["SUCCESS", "FAILED", "CANCELLED"]:
            # Idempotent or invalid state, do not process again
            return TransactionResponse.model_validate(tx)

        if tx.status != "PENDING":
            raise BusinessLogicError(f"Cannot simulate success for transaction in status: {tx.status}")

        if not tx.bill_id:
            raise BusinessLogicError("Transaction has no associated bill.")

        # Lock the associated bill
        bill = await self.bill_repo.get_with_lock(tx.bill_id)
        if not bill:
            raise EntityNotFoundError("Associated bill not found.")

        if bill.status == "PAID":
            raise BusinessLogicError("Bill is already paid.")

        # Atomically update both
        tx.status = "SUCCESS"
        tx.provider = "MOCK"
        tx.provider_reference = f"MOCK-REF-{uuid.uuid4().hex[:8].upper()}"

        bill.status = "PAID"
        bill.amount_due = Decimal("0.00")

        # Session flush / commit
        await self.db.commit()
        
        # It's important to refresh to return the actual saved values
        await self.db.refresh(tx)
        return TransactionResponse.model_validate(tx)

    def _build_prepare_response(self, tx: Transaction) -> PaymentPrepareResponse:
        return PaymentPrepareResponse(
            transaction_id=tx.id,
            bill_id=tx.bill_id,
            amount=tx.amount,
            currency=tx.currency,
            status=tx.status
        )
