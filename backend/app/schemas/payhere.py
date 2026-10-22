"""
PayHere-specific Pydantic schemas.

PayHereInitiateResponse  — returned to Flutter so it can launch the PayHere SDK.
PayHereCallbackPayload   — parsed from the server-to-server form POST from PayHere.
"""
from pydantic import BaseModel, ConfigDict
from typing import Optional


class PayHereInitiateResponse(BaseModel):
    """
    All fields Flutter needs to launch the PayHere SDK checkout.
    The hash is computed server-side using PAYHERE_SECRET which is never exposed.
    """
    merchant_id: str
    order_id: str       # = transaction.id (UUID string)
    items: str          # Human-readable bill description
    currency: str
    amount: str         # Formatted to 2 decimal places as a string, e.g. "100.00"
    first_name: str
    last_name: str
    email: str
    phone: str
    address: str
    city: str
    country: str
    return_url: str
    cancel_url: str
    notify_url: str
    hash: str           # MD5 signature computed server-side


class PayHereCallbackPayload(BaseModel):
    """
    Fields sent by PayHere via server-to-server form POST to /payhere/callback.
    PayHere may include additional fields; extra="allow" captures them for logging.
    """
    merchant_id: str
    order_id: str           # = transaction.id we set as order_id during initiation
    payhere_amount: str     # Amount as formatted string, e.g. "100.00"
    payhere_currency: str
    status_code: str        # "2"=success, "0"=pending, "-1"=cancelled, "-2"=failed, "-3"=chargeback
    md5sig: str             # PayHere-computed signature we must verify
    payment_id: Optional[str] = None  # PayHere's own internal payment reference

    model_config = ConfigDict(extra="allow")  # Capture any additional fields PayHere sends
