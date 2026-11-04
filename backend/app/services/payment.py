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
from app.services.payhere_retrieval import PayHereRetrievalClient

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

        # --- Load bill for item description and enforce payment safety checks ---
        bill_description: str | None = None
        if tx.bill_id:
            bill = await self.bill_repo.get_with_lock(tx.bill_id)
            if not bill or bill.user_id != user_id:
                raise EntityNotFoundError("Associated bill not found or does not belong to user.")
            if bill.status == "PAID":
                raise BusinessLogicError(
                    "This bill has already been paid. This payment attempt can no longer be initiated."
                )
            if bill.status != "UNPAID":
                raise BusinessLogicError(
                    f"Cannot initiate payment for bill in status: {bill.status}"
                )
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
                if bill.status == "PAID":
                    logger.warning(
                        "Duplicate payment detected for bill %s. Transaction %s received SUCCESS, "
                        "but bill was already PAID. Preserving transaction SUCCESS without re-applying bill settlement.",
                        bill.id,
                        tx.id,
                    )
                else:
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

        # 1. Lock bill row & verify ownership
        bill = await self.bill_repo.get_with_lock(req.bill_id)
        if not bill or bill.user_id != user_id:
            raise EntityNotFoundError("Bill not found or does not belong to user.")

        # 2 & 3. Verify bill is still UNPAID
        if bill.status != "UNPAID":
            raise BusinessLogicError(f"Cannot pay bill in status: {bill.status}")

        # Validate Payment Method
        pm = await self.pm_repo.get_by_user(req.payment_method_id, user_id)
        if not pm:
            raise EntityNotFoundError("Payment method not found or does not belong to user.")

        # 4 & 5. Check existing active PENDING transaction for this bill and user
        existing_pending = await self.tx_repo.get_pending_by_bill_and_user(req.bill_id, user_id)
        if existing_pending:
            return self._build_prepare_response(existing_pending)

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

    async def reconcile_pending_transaction(
        self,
        tx_id: uuid.UUID,
        user_id: uuid.UUID,
        retrieval_client: Optional[PayHereRetrievalClient] = None,
    ) -> TransactionResponse:
        """
        Safely reconcile a PENDING transaction with PayHere Merchant Retrieval API.

        Flow:
        1. Lock transaction row using SELECT FOR UPDATE.
        2. Ownership check: transaction must belong to authenticated user (404 on mismatch).
        3. If transaction is already terminal (SUCCESS / FAILED / CANCELLED):
           return current TransactionResponse unchanged without querying PayHere.
        4. If transaction is not PENDING, raise BusinessLogicError.
        5. Call PayHereRetrievalClient with order_id = str(transaction.id).
        6. Validate retrieved fields (order_id, amount, currency) against transaction.
           Raise BusinessLogicError on mismatch (no DB mutation).
        7. State transitions:
           - SUCCESS: tx.status="SUCCESS", tx.provider="PAYHERE", provider_reference set if available;
                      if tx.bill_id, lock bill, bill.status="PAID", bill.amount_due=Decimal("0.00");
                      atomic commit.
           - FAILED:  tx.status="FAILED", tx.provider="PAYHERE", provider_reference set if available;
                      bill untouched; commit.
           - PENDING: tx.status unchanged; provider set to PAYHERE if not already;
                      provider_reference set if returned; commit if changed.
           - NOT_FOUND: tx remains PENDING; return unchanged (no failure, no mutation).
        """
        # 1. Lock transaction row using SELECT FOR UPDATE
        tx = await self.tx_repo.get_with_lock(tx_id)

        # 2. Ownership check (identical 404 to prevent enumeration)
        if not tx or tx.user_id != user_id:
            raise EntityNotFoundError("Transaction not found or does not belong to user.")

        # 3. If transaction is already terminal, return unchanged without calling PayHere
        if tx.status in ["SUCCESS", "FAILED", "CANCELLED"]:
            return TransactionResponse.model_validate(tx)

        # 4. Only PENDING transactions may be reconciled
        if tx.status != "PENDING":
            raise BusinessLogicError(
                f"Cannot reconcile transaction in status: {tx.status}. Only PENDING transactions may be reconciled."
            )

        # 5. Call PayHereRetrievalClient using order_id = str(transaction.id)
        client = retrieval_client or PayHereRetrievalClient()
        result = await client.retrieve_payment(order_id=str(tx.id))

        # 6. Validate retrieved payment before mutating local state
        if result.order_id and str(result.order_id).strip() != str(tx.id):
            raise BusinessLogicError(
                f"PayHere retrieval order_id mismatch: expected {tx.id}, got {result.order_id}"
            )
        if result.amount is not None and result.amount != tx.amount:
            raise BusinessLogicError(
                f"PayHere retrieval amount mismatch: expected {tx.amount}, got {result.amount}"
            )
        if result.currency and result.currency.strip().upper() != tx.currency.strip().upper():
            raise BusinessLogicError(
                f"PayHere retrieval currency mismatch: expected {tx.currency}, got {result.currency}"
            )

        # 7. State transitions
        if result.status == "SUCCESS":
            tx.status = "SUCCESS"
            tx.provider = "PAYHERE"
            if result.provider_reference:
                tx.provider_reference = result.provider_reference

            if tx.bill_id:
                bill = await self.bill_repo.get_with_lock(tx.bill_id)
                if not bill or bill.user_id != tx.user_id:
                    raise BusinessLogicError("Transaction has invalid associated bill.")
                if bill.status == "PAID":
                    logger.warning(
                        "Duplicate payment detected for bill %s. Transaction %s received SUCCESS, "
                        "but bill was already PAID. Preserving transaction SUCCESS without re-applying bill settlement.",
                        bill.id,
                        tx.id,
                    )
                else:
                    bill.status = "PAID"
                    bill.amount_due = Decimal("0.00")

            await self.db.commit()
            await self.db.refresh(tx)
            return TransactionResponse.model_validate(tx)

        elif result.status == "FAILED":
            tx.status = "FAILED"
            tx.provider = "PAYHERE"
            if result.provider_reference:
                tx.provider_reference = result.provider_reference

            await self.db.commit()
            await self.db.refresh(tx)
            return TransactionResponse.model_validate(tx)

        elif result.status == "PENDING":
            updated = False
            if tx.provider != "PAYHERE":
                tx.provider = "PAYHERE"
                updated = True
            if result.provider_reference and tx.provider_reference != result.provider_reference:
                tx.provider_reference = result.provider_reference
                updated = True

            if updated:
                await self.db.commit()
                await self.db.refresh(tx)
            return TransactionResponse.model_validate(tx)

        elif result.status == "NOT_FOUND":
            # Leave transaction PENDING, do not mark FAILED or CANCELLED, do not mutate DB
            return TransactionResponse.model_validate(tx)

        else:
            raise BusinessLogicError(f"Unsupported PayHere retrieval status: {result.status}")

    def _build_prepare_response(self, tx: Transaction) -> PaymentPrepareResponse:
        return PaymentPrepareResponse(
            transaction_id=tx.id,
            bill_id=tx.bill_id,
            amount=tx.amount,
            currency=tx.currency,
            status=tx.status
        )
