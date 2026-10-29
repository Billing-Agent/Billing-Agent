"""
Payment Intent recognition and classification for Phase 8B.

Phase 8B is strictly non-executing.
This module classifies conversational user intent into:
- READ_BILLS: Questions inspecting, viewing, or querying bills.
- PAY_BILL: Explicit or implicit intent to pay/settle a bill.
- UNKNOWN: Generic or unclassified conversational input.
"""
import re
from enum import Enum
from typing import List, Optional


class AgentIntent(str, Enum):
    READ_BILLS = "READ_BILLS"
    PAY_BILL = "PAY_BILL"
    UNKNOWN = "UNKNOWN"


CONFIRMATION_PHRASES = {
    "yes",
    "confirm",
    "go ahead",
    "do it",
    "proceed",
    "yes please",
    "sure",
    "i confirm",
    "confirm payment",
}

PAYMENT_KEYWORDS = {
    "pay",
    "settle",
    "payment",
    "checkout",
}

READ_KEYWORDS = {
    "show",
    "view",
    "check",
    "how much",
    "what is",
    "list",
    "details",
    "see",
}

CONFIRMATION_RECEIVED_MESSAGE = (
    "Your confirmation has been received, but payment execution is not enabled in this phase."
)


def is_confirmation_message(message: str) -> bool:
    """Check if the user input is a confirmation phrase."""
    if not message:
        return False
    normalized = re.sub(r"[^\w\s]", "", message.strip().lower()).strip()
    return normalized in CONFIRMATION_PHRASES


def detect_intent(
    message: str,
    executed_tools: Optional[List[str]] = None,
) -> str:
    """
    Detect conversational intent based on executed tools and user message semantics.

    Tool execution takes precedence as deterministic evidence of intent.
    """
    executed = executed_tools or []

    # If payment planning tools were called
    if any(t in executed for t in ("plan_bill_payment", "create_payment_plan")):
        return AgentIntent.PAY_BILL.value

    # If read-only tools were called without payment tools
    if any(t in executed for t in ("get_user_bills", "get_bill_by_id", "find_bill")):
        return AgentIntent.READ_BILLS.value

    # Analyze message keywords
    msg_lower = message.lower()
    words = set(re.findall(r"\b\w+\b", msg_lower))

    # Payment intent keywords
    if any(k in words for k in PAYMENT_KEYWORDS):
        return AgentIntent.PAY_BILL.value

    # Confirmation phrases represent affirmative payment intent in confirmation turns
    if is_confirmation_message(message):
        return AgentIntent.PAY_BILL.value

    # Read intent keywords
    if any(k in words for k in READ_KEYWORDS) or "how much" in msg_lower or "what is" in msg_lower:
        return AgentIntent.READ_BILLS.value

    return AgentIntent.UNKNOWN.value
