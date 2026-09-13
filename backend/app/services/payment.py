import uuid
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

class PaymentService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.tx_repo = TransactionRepository(db)
        self.bill_repo = BillRepository(db)
        self.pm_repo = PaymentMethodRepository(db)

    async def get_user_payment_methods(self, user_id: uuid.UUID):
        return await self.pm_repo.get_all_by_user(user_id)

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
