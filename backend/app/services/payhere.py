"""
PayHereService — isolated service containing all PayHere-specific logic.

Responsibilities:
  - build_initiate_params : assemble and sign checkout parameters for Flutter
  - verify_callback_signature : recompute MD5 and compare against PayHere's md5sig
  - map_status_code : translate PayHere integer status codes to internal TX statuses

This service intentionally performs NO database access and makes NO outbound HTTP
calls.  The PayHere Checkout flow only requires the backend to generate signed
parameters; actual payment capture happens in PayHere's hosted checkout, and the
result is reported back via a server-to-server callback (handled in the endpoint
layer with PaymentService).
"""
import hashlib
import logging
from decimal import Decimal, InvalidOperation
from typing import Optional

from app.core.config import settings
from app.core.exceptions import BusinessLogicError
from app.models.transaction import Transaction
from app.models.user import User
from app.schemas.payhere import PayHereInitiateResponse

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Internal PayHere status_code → internal transaction status mapping
# ---------------------------------------------------------------------------
_PAYHERE_STATUS_MAP: dict[str, str] = {
    "2":  "SUCCESS",
    "0":  "PENDING",
    "-1": "CANCELLED",
    "-2": "FAILED",
    "-3": "FAILED",   # Chargedback — treated as FAILED internally
}


class PayHereService:
    """Pure logic service: no DB session, no outbound HTTP."""

    # ------------------------------------------------------------------
    # Checkout parameter builder
    # ------------------------------------------------------------------

    def build_initiate_params(
        self,
        transaction: Transaction,
        user: User,
        bill_description: Optional[str] = None,
    ) -> PayHereInitiateResponse:
        """
        Assemble and sign the PayHere checkout parameters.

        Raises BusinessLogicError if required configuration (merchant ID / secret /
        callback URLs) is missing, or if the user has insufficient profile data
        (missing phone).

        The hash is computed using PAYHERE_SECRET which is never included in the
        returned response — only the resulting hash string is returned.
        """
        self._assert_config_complete()

        # ----- Resolve payer identity from User ---------------------------------
        first_name, last_name = self._split_name(user.name)
        phone = self._require_phone(user.phone)

        # ----- Format amount exactly as PayHere expects -------------------------
        amount_str = f"{transaction.amount:.2f}"

        # ----- Compute hash (PAYHERE_SECRET stays server-side) ------------------
        order_id = str(transaction.id)
        computed_hash = self._compute_hash(
            merchant_id=settings.PAYHERE_MERCHANT_ID,
            order_id=order_id,
            amount_str=amount_str,
            currency=transaction.currency,
        )

        # ----- Bill description -------------------------------------------------
        items = bill_description or f"Bill payment (transaction {order_id[:8]})"

        return PayHereInitiateResponse(
            merchant_id=settings.PAYHERE_MERCHANT_ID,
            order_id=order_id,
            items=items,
            currency=transaction.currency,
            amount=amount_str,
            first_name=first_name,
            last_name=last_name,
            email=user.email,
            phone=phone,
            address=settings.PAYHERE_DEFAULT_ADDRESS,
            city=settings.PAYHERE_DEFAULT_CITY,
            country=settings.PAYHERE_DEFAULT_COUNTRY,
            return_url=settings.PAYHERE_RETURN_URL or "",
            cancel_url=settings.PAYHERE_CANCEL_URL or "",
            notify_url=settings.PAYHERE_NOTIFY_URL or "",
            hash=computed_hash,
        )

    # ------------------------------------------------------------------
    # Callback signature verification
    # ------------------------------------------------------------------

    def verify_callback_signature(
        self,
        *,
        merchant_id: str,
        order_id: str,
        payhere_amount: str,
        payhere_currency: str,
        status_code: str,
        md5sig: str,
    ) -> bool:
        """
        Recompute the PayHere MD5 signature and compare against the received md5sig.

        Formula (from PayHere docs):
            hashed_secret = UPPERCASE( MD5( merchant_secret ) )
            local_sig     = UPPERCASE( MD5( merchant_id + order_id + payhere_amount
                                            + payhere_currency + status_code
                                            + hashed_secret ) )

        Returns True if signatures match, False otherwise.
        Logs a warning (without revealing the secret) if configuration is missing.
        """
        if not settings.PAYHERE_SECRET:
            logger.error(
                "PAYHERE_SECRET is not configured — cannot verify callback signature."
            )
            return False

        hashed_secret = _md5_upper(settings.PAYHERE_SECRET)
        data_string = (
            merchant_id
            + order_id
            + payhere_amount
            + payhere_currency
            + status_code
            + hashed_secret
        )
        local_sig = _md5_upper(data_string)
        return local_sig == md5sig.upper()

    # ------------------------------------------------------------------
    # Secondary callback validations (beyond signature)
    # ------------------------------------------------------------------

    def validate_callback_fields(
        self,
        *,
        merchant_id: str,
        payhere_amount: str,
        payhere_currency: str,
        transaction: Transaction,
    ) -> None:
        """
        After verifying the signature, perform secondary field-level checks:
          1. merchant_id in callback == configured PAYHERE_MERCHANT_ID
          2. Decimal(payhere_amount) == transaction.amount
          3. payhere_currency == transaction.currency

        Raises BusinessLogicError with a descriptive message on any mismatch.
        The caller should log the mismatch and return an appropriate error response
        WITHOUT updating the transaction.
        """
        configured_merchant_id = settings.PAYHERE_MERCHANT_ID or ""
        if merchant_id != configured_merchant_id:
            raise BusinessLogicError(
                f"Callback merchant_id '{merchant_id}' does not match "
                f"configured PAYHERE_MERCHANT_ID."
            )

        try:
            callback_amount = Decimal(payhere_amount)
        except InvalidOperation:
            raise BusinessLogicError(
                f"Callback payhere_amount '{payhere_amount}' is not a valid decimal."
            )

        if callback_amount != transaction.amount:
            raise BusinessLogicError(
                f"Callback amount {callback_amount} does not match "
                f"transaction amount {transaction.amount} for tx {transaction.id}."
            )

        if payhere_currency != transaction.currency:
            raise BusinessLogicError(
                f"Callback currency '{payhere_currency}' does not match "
                f"transaction currency '{transaction.currency}' for tx {transaction.id}."
            )

    # ------------------------------------------------------------------
    # Status code mapping
    # ------------------------------------------------------------------

    def map_status_code(self, status_code: str) -> Optional[str]:
        """
        Map a PayHere status_code string to an internal transaction status string.

        Returns None for unknown/unrecognised codes so the caller can decide how
        to handle them (log and skip rather than silently set a bad state).
        """
        return _PAYHERE_STATUS_MAP.get(status_code)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _assert_config_complete(self) -> None:
        """Raise BusinessLogicError if any required PayHere config is absent."""
        missing: list[str] = []
        if not settings.PAYHERE_MERCHANT_ID:
            missing.append("PAYHERE_MERCHANT_ID")
        if not settings.PAYHERE_SECRET:
            missing.append("PAYHERE_SECRET")
        if not settings.PAYHERE_NOTIFY_URL:
            missing.append("PAYHERE_NOTIFY_URL")
        if missing:
            raise BusinessLogicError(
                f"PayHere integration is not fully configured. "
                f"Missing settings: {', '.join(missing)}."
            )

    @staticmethod
    def _split_name(full_name: str) -> tuple[str, str]:
        """Split 'First Last' into ('First', 'Last'). Handles single-word names."""
        parts = full_name.strip().split(maxsplit=1)
        first = parts[0] if parts else ""
        last = parts[1] if len(parts) > 1 else ""
        return first, last

    @staticmethod
    def _require_phone(phone: Optional[str]) -> str:
        """
        Return the user's phone number or raise if unavailable.
        Per design: we do NOT invent placeholder phone numbers.
        """
        if not phone:
            raise BusinessLogicError(
                "A phone number is required to initiate a PayHere payment. "
                "Please add a phone number to your account."
            )
        return phone

    def _compute_hash(
        self,
        *,
        merchant_id: str,
        order_id: str,
        amount_str: str,
        currency: str,
    ) -> str:
        """
        Compute the PayHere initiation hash.
        Uses PAYHERE_SECRET internally; the secret is never returned to the caller.

        Formula:
            hashed_secret = UPPERCASE( MD5( merchant_secret ) )
            hash          = UPPERCASE( MD5( merchant_id + order_id + amount
                                            + currency + hashed_secret ) )
        """
        hashed_secret = _md5_upper(settings.PAYHERE_SECRET)
        data_string = merchant_id + order_id + amount_str + currency + hashed_secret
        return _md5_upper(data_string)


# ---------------------------------------------------------------------------
# Module-level utility
# ---------------------------------------------------------------------------

def _md5_upper(value: str) -> str:
    """Return the uppercase hex MD5 digest of the given UTF-8 string."""
    return hashlib.md5(value.encode("utf-8")).hexdigest().upper()
