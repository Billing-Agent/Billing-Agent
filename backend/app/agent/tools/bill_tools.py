"""
Read-only bill tools for Google ADK Billing Agent.

Ownership & Safety:
- All tools operate strictly within the authenticated user's context (BillingAgentContext).
- No parameters allow the LLM or user to supply an arbitrary user_id.
- No database mutations, state alterations, or payment executions are permitted.
"""
import re
from uuid import UUID
from typing import Any, Dict, List, Optional

from app.agent.context import BillingAgentContext
from app.models.bill import Bill

BILLER_NORMALIZATION = {
    "electricity": "CEB",
    "power": "CEB",
    "ceb": "CEB",
    "water": "WATER",
    "dialog": "DIALOG",
    "slt": "SLT",
}


def safe_bill_dict(bill: Bill) -> Dict[str, Any]:
    """Serialize a Bill model into a clean, safe dictionary with no internal ORM or private user identifiers."""
    return {
        "id": str(bill.id),
        "biller": bill.biller,
        "account_number": bill.account_number,
        "customer_name": bill.customer_name,
        "amount_due": f"{bill.amount_due:.2f}",
        "currency": bill.currency,
        "status": bill.status,
        "due_date": bill.due_date,
    }


class BillTools:
    """
    Read-only billing tools scoped strictly to the authenticated user via BillingAgentContext.
    No methods perform DB mutations or payment operations.
    """

    def __init__(self, context: BillingAgentContext):
        self.context = context

    async def get_user_bills(self) -> Dict[str, Any]:
        """Retrieve all bills registered to the authenticated user.

        Returns:
            Dictionary containing a list of the user's bills with biller, account number, amount due, and status.
        """
        bills = await self.context.billing_service.get_user_bills(self.context.authenticated_user_id)
        return {
            "status": "success",
            "count": len(bills),
            "bills": [safe_bill_dict(b) for b in bills],
        }

    async def get_bill_by_id(self, bill_id: str) -> Dict[str, Any]:
        """Retrieve a specific bill by its ID, strictly validating ownership by the authenticated user.

        Args:
            bill_id: The unique UUID string of the bill.

        Returns:
            Dictionary containing the bill details if found and owned by the authenticated user, or an error.
        """
        try:
            bill_uuid = UUID(str(bill_id).strip())
        except (ValueError, TypeError, AttributeError):
            return {"status": "error", "message": f"Invalid bill ID format: {bill_id}"}

        # Query using get_by_user to enforce ownership at the repository layer
        bill = await self.context.billing_service.repo.get_by_user(
            bill_uuid, self.context.authenticated_user_id
        )
        if not bill:
            return {"status": "not_found", "message": "Bill not found or does not belong to user."}

        return {"status": "success", "bill": safe_bill_dict(bill)}

    async def find_bill(
        self,
        query: str = "",
        biller: Optional[str] = None,
        account_number: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Search and find bills belonging to the authenticated user by biller, utility type, or account number.

        Args:
            query: General search query text (e.g., 'electricity bill', 'water', 'account 12345').
            biller: Specific biller name or alias (e.g., 'CEB', 'electricity', 'water', 'dialog', 'slt').
            account_number: Specific account number if mentioned by the user (e.g. '12346').

        Returns:
            Dictionary with found bill, list of multiple matching candidate bills for clarification, or not_found status.
        """
        bills = await self.context.billing_service.get_user_bills(self.context.authenticated_user_id)
        if not bills:
            return {"status": "not_found", "message": "You currently have no registered bills."}

        # 1. Normalize biller
        target_biller = None
        if biller and biller.strip():
            b_clean = biller.strip().lower()
            target_biller = BILLER_NORMALIZATION.get(b_clean, biller.strip().upper())
        elif query and query.strip():
            q_lower = query.lower()
            for key, val in BILLER_NORMALIZATION.items():
                if re.search(r"\b" + re.escape(key) + r"\b", q_lower):
                    target_biller = val
                    break

        # 2. Extract account number from input or query
        target_account = None
        if account_number and account_number.strip():
            target_account = account_number.strip()
        elif query and query.strip():
            for b in bills:
                if b.account_number in query:
                    target_account = b.account_number
                    break

        # 3. Filter bills
        candidates = list(bills)
        if target_biller:
            candidates = [b for b in candidates if b.biller.upper() == target_biller.upper()]

        if target_account:
            candidates = [b for b in candidates if target_account.lower() in b.account_number.lower()]

        if not candidates and target_biller:
            return {
                "status": "not_found",
                "message": f"No bills found for biller '{target_biller}'.",
            }

        if len(candidates) == 1:
            return {
                "status": "found",
                "bill": safe_bill_dict(candidates[0]),
                "message": f"Found bill for {candidates[0].biller} (Account: {candidates[0].account_number}).",
            }
        elif len(candidates) > 1:
            return {
                "status": "multiple_matches",
                "count": len(candidates),
                "bills": [safe_bill_dict(b) for b in candidates],
                "message": (
                    f"Found {len(candidates)} matching bills. Please ask the user to clarify which account number they are referring to: "
                    + ", ".join([f"{b.biller} (Account: {b.account_number})" for b in candidates])
                ),
            }
        else:
            return {
                "status": "not_found",
                "message": f"No bills found matching '{query or biller or account_number}'.",
            }

    def get_tools(self) -> List[Any]:
        return [self.get_user_bills, self.get_bill_by_id, self.find_bill]
