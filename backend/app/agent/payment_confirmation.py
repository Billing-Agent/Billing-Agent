"""
Payment Confirmation storage and validation for Phase 8C.

NON-PRODUCTION / PROTOTYPE IN-MEMORY STORE:
- Process-local, in-memory store suitable for local development / testing.
- Not backed by Redis or database tables yet.
- Enforces short-lived TTL (default: 5 minutes) and single-use consumption.
- Immutable trusted facts (user_id, bill_id, amount, currency) are established
  strictly from backend database records during payment planning, NEVER from the LLM or client.
"""
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
import threading
from typing import Dict, Optional
from uuid import UUID, uuid4

from app.core.config import settings


@dataclass
class PaymentConfirmation:
    """
    Short-lived, single-use server-controlled authorization object for a payment plan.
    """
    confirmation_id: str
    user_id: UUID
    bill_id: UUID
    amount: str
    currency: str
    created_at: datetime
    expires_at: datetime
    consumed: bool = False
    idempotency_key: str = field(default_factory=lambda: str(uuid4()))

    def is_expired(self) -> bool:
        """Check if the confirmation object has exceeded its TTL."""
        return datetime.now(timezone.utc) >= self.expires_at


class PaymentConfirmationStore:
    """
    Thread-safe, process-local confirmation store for Phase 8C development/prototype.
    """

    def __init__(self):
        self._store: Dict[str, PaymentConfirmation] = {}
        self._lock = threading.Lock()

    def create_confirmation(
        self,
        user_id: UUID,
        bill_id: UUID,
        amount: str,
        currency: str,
        ttl_seconds: Optional[int] = None,
    ) -> PaymentConfirmation:
        """
        Create and record a new payment confirmation token tied to verified backend bill data.
        """
        ttl = ttl_seconds if ttl_seconds is not None else settings.PAYMENT_CONFIRMATION_TTL_SECONDS
        now = datetime.now(timezone.utc)
        conf_id = str(uuid4())
        conf = PaymentConfirmation(
            confirmation_id=conf_id,
            user_id=user_id,
            bill_id=bill_id,
            amount=amount,
            currency=currency,
            created_at=now,
            expires_at=now + timedelta(seconds=ttl),
            consumed=False,
            idempotency_key=f"agent_confirm_{conf_id}",
        )
        with self._lock:
            self._store[conf_id] = conf
        return conf

    def get(self, confirmation_id: str) -> Optional[PaymentConfirmation]:
        """Retrieve a confirmation object by its opaque token."""
        with self._lock:
            return self._store.get(confirmation_id)

    def mark_consumed(self, confirmation_id: str) -> bool:
        """
        Mark a confirmation as consumed (single-use enforcement).
        Returns True if marked consumed, or False if already consumed or not found.
        """
        with self._lock:
            conf = self._store.get(confirmation_id)
            if conf and not conf.consumed:
                conf.consumed = True
                return True
            return False

    def clear(self):
        """Clear all stored confirmations (used for test isolation)."""
        with self._lock:
            self._store.clear()


# Process-local singleton store
confirmation_store = PaymentConfirmationStore()
