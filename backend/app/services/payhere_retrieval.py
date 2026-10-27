"""
PayHereRetrievalClient — isolated client for the PayHere Merchant Retrieval API.

Responsibilities:
  1. Obtain OAuth access token via client credentials grant using HTTP Basic Auth
  2. Query payment status by order_id
  3. Parse PayHere response and normalize into PayHerePaymentRetrievalResult
  4. Perform NO database access

Security:
  - Flutter must NEVER call this API directly.
  - App ID and App Secret are NEVER logged.
  - OAuth tokens are in-memory only (never persisted to the database).
"""
import logging
from decimal import Decimal, InvalidOperation
from typing import Optional
import httpx

from app.core.config import settings
from app.core.exceptions import BusinessLogicError
from app.schemas.payhere import PayHerePaymentRetrievalResult

logger = logging.getLogger(__name__)


class PayHereRetrievalClient:
    """Client for PayHere Merchant Retrieval API."""

    def __init__(
        self,
        base_url: Optional[str] = None,
        app_id: Optional[str] = None,
        app_secret: Optional[str] = None,
    ):
        self.base_url = (base_url or settings.PAYHERE_MERCHANT_API_BASE_URL).rstrip("/")
        self.app_id = app_id or settings.PAYHERE_API_APP_ID
        self.app_secret = app_secret or settings.PAYHERE_API_APP_SECRET

    def _validate_credentials(self) -> None:
        """Ensure App ID and App Secret are configured."""
        if not self.app_id or not self.app_secret:
            raise BusinessLogicError(
                "PayHere Retrieval API credentials (APP_ID / APP_SECRET) are not configured."
            )

    async def get_access_token(self, client: Optional[httpx.AsyncClient] = None) -> str:
        """
        Request an OAuth access token using client_credentials grant with HTTP Basic Auth.
        """
        self._validate_credentials()
        token_url = f"{self.base_url}/oauth/token"

        manage_client = client is None
        async_client = client or httpx.AsyncClient()

        try:
            res = await async_client.post(
                token_url,
                auth=(self.app_id, self.app_secret),
                data={"grant_type": "client_credentials"},
                timeout=10.0,
            )
        except Exception:
            logger.error("PayHere OAuth connection error")
            raise BusinessLogicError("Failed to connect to PayHere OAuth service.")
        finally:
            if manage_client:
                await async_client.aclose()

        if res.status_code != 200:
            logger.error("PayHere OAuth token request failed with status: %d", res.status_code)
            raise BusinessLogicError(f"Failed to obtain PayHere OAuth token (status {res.status_code}).")

        try:
            token_json = res.json()
        except Exception:
            raise BusinessLogicError("Failed to parse PayHere OAuth token response.")

        access_token = token_json.get("access_token")
        if not access_token:
            raise BusinessLogicError("PayHere OAuth response did not contain an access_token.")

        return access_token

    async def retrieve_payment(
        self,
        order_id: str,
        client: Optional[httpx.AsyncClient] = None,
    ) -> PayHerePaymentRetrievalResult:
        """
        Query PayHere for payment status corresponding to order_id (which equals transaction.id).
        """
        manage_client = client is None
        async_client = client or httpx.AsyncClient()

        try:
            access_token = await self.get_access_token(client=async_client)

            search_url = f"{self.base_url}/payment/search?order_id={order_id}"
            try:
                search_res = await async_client.get(
                    search_url,
                    headers={"Authorization": f"Bearer {access_token}"},
                    timeout=10.0,
                )
            except Exception:
                logger.error("PayHere payment search connection error")
                raise BusinessLogicError("Failed to connect to PayHere payment search service.")

            if search_res.status_code == 404:
                return PayHerePaymentRetrievalResult(status="NOT_FOUND", order_id=order_id)

            if search_res.status_code != 200:
                logger.error("PayHere payment search failed with status: %d", search_res.status_code)
                raise BusinessLogicError(
                    f"PayHere payment search returned unexpected HTTP status {search_res.status_code}."
                )

            try:
                res_json = search_res.json()
            except Exception:
                raise BusinessLogicError("Failed to parse PayHere payment search response.")

            return self._parse_search_response(res_json, order_id)
        finally:
            if manage_client:
                await async_client.aclose()

    def _parse_search_response(
        self,
        res_json: dict,
        order_id: str,
    ) -> PayHerePaymentRetrievalResult:
        """
        Normalize the PayHere search response into PayHerePaymentRetrievalResult.

        Status code mapping:
          1  -> SUCCESS
          0  -> PENDING
          -1 -> NOT_FOUND
          -2 -> FAILED
        """
        raw_status = res_json.get("status")
        if raw_status is None:
            raise BusinessLogicError("PayHere retrieval response missing 'status' field.")

        status_str = str(raw_status).strip()
        if status_str not in ("1", "0", "-1", "-2"):
            raise BusinessLogicError(f"Unknown PayHere retrieval status code: {raw_status}")

        if status_str == "-1":
            return PayHerePaymentRetrievalResult(status="NOT_FOUND", order_id=order_id)

        # Extract payment payload from data (if wrapped)
        data = res_json.get("data")
        item: dict = {}
        if isinstance(data, list):
            if len(data) == 0:
                # Empty data array means payment was not found
                return PayHerePaymentRetrievalResult(status="NOT_FOUND", order_id=order_id)
            if isinstance(data[0], dict):
                item = data[0]
        elif isinstance(data, dict):
            item = data
        elif isinstance(res_json, dict):
            item = res_json

        if status_str == "0":
            return PayHerePaymentRetrievalResult(
                status="PENDING",
                provider_reference=str(item.get("payment_id")) if item.get("payment_id") else None,
                amount=self._parse_amount(item.get("amount")),
                currency=item.get("currency"),
                order_id=item.get("order_id") or order_id,
            )

        if status_str == "-2":
            return PayHerePaymentRetrievalResult(
                status="FAILED",
                provider_reference=str(item.get("payment_id")) if item.get("payment_id") else None,
                amount=self._parse_amount(item.get("amount")),
                currency=item.get("currency"),
                order_id=item.get("order_id") or order_id,
            )

        if status_str == "1":
            # If the individual payment record inside data has its own status:
            item_status = item.get("status")
            final_status = "SUCCESS"
            if item_status is not None:
                item_status_str = str(item_status).strip().upper()
                if item_status_str in ("1", "2", "RECEIVED", "SUCCESS"):
                    final_status = "SUCCESS"
                elif item_status_str in ("0", "PENDING"):
                    final_status = "PENDING"
                elif item_status_str in ("-1", "NOT_FOUND"):
                    final_status = "NOT_FOUND"
                elif item_status_str in ("-2", "FAILED", "DECLINED", "CANCELLED"):
                    final_status = "FAILED"
                else:
                    raise BusinessLogicError(f"Unknown PayHere payment item status: {item_status}")

            return PayHerePaymentRetrievalResult(
                status=final_status,
                provider_reference=str(item.get("payment_id")) if item.get("payment_id") else None,
                amount=self._parse_amount(item.get("amount")),
                currency=item.get("currency"),
                order_id=item.get("order_id") or order_id,
            )

        raise BusinessLogicError(f"Unknown PayHere retrieval status code: {raw_status}")

    @staticmethod
    def _parse_amount(val) -> Optional[Decimal]:
        if val is None:
            return None
        try:
            return Decimal(str(val))
        except (InvalidOperation, TypeError, ValueError):
            raise BusinessLogicError(f"Invalid amount format in PayHere response: {val}")
