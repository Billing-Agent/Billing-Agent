"""
Deterministic payment planning tools for Phase 8B Billing Agent.

Safety & Non-Execution Guarantees:
- Phase 8B is STRICTLY NON-EXECUTING.
- All tools operate strictly within the authenticated user's context (BillingAgentContext).
- No parameters allow the LLM or client to provide or override the user_id.
- No amount parameter is accepted: amounts are deterministically read from the database bill record.
- Bills are strictly checked for eligibility (must exist, belong to user, and have status == "UNPAID").
- If a bill is already "PAID", payment planning is rejected safely.
- If multiple bills match, no plan is created; candidate accounts are returned for user clarification.
- Performs ZERO database writes, creates NO transactions, and invokes NO external payment services.
"""
import re
from typing import Any, Dict, List, Optional
from uuid import UUID

from app.agent.context import BillingAgentContext
from app.agent.tools.bill_tools import BILLER_NORMALIZATION
from app.schemas.agent import PaymentPlan


class PaymentPlanTools:
    """
    Deterministic payment planning tools scoped strictly to the authenticated user.
    """

    def __init__(self, context: BillingAgentContext):
        self.context = context
        self.active_plan: Optional[PaymentPlan] = None
        self.executed: bool = False

    async def plan_bill_payment(
        self,
        query: str = "",
        biller: Optional[str] = None,
        account_number: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Plan a proposed bill payment for the authenticated user and request confirmation.

        This tool resolves the target bill, validates eligibility (status must be UNPAID),
        reads the exact amount due from the database, and creates a proposed PaymentPlan.
        DOES NOT execute any payment or write to the database.

        Args:
            query: Natural language query (e.g. 'Pay my electricity bill', 'Pay account 12346').
            biller: Biller name or utility alias (e.g. 'CEB', 'electricity', 'water', 'dialog', 'slt').
            account_number: Specific account number to pay (e.g. '12346').

        Returns:
            Dictionary with the payment plan result, multiple matches clarification, or not_found / not_payable message.
        """
        self.executed = True
        self.active_plan = None
        bills = await self.context.billing_service.get_user_bills(self.context.authenticated_user_id)
        if not bills:
            return {
                "status": "not_found",
                "message": "You currently have no registered bills to pay.",
            }

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

        # 3. Filter candidates
        candidates = list(bills)
        if target_biller:
            candidates = [b for b in candidates if b.biller.upper() == target_biller.upper()]

        if target_account:
            candidates = [b for b in candidates if target_account.lower() in b.account_number.lower()]

        # 4. Handle 0 matches
        if not candidates:
            searched_item = target_biller or target_account or query or "your query"
            return {
                "status": "not_found",
                "message": f"No bills found matching '{searched_item}'.",
            }

        # 5. Handle Multiple Matches
        if len(candidates) > 1:
            candidates_formatted = "\n".join(
                [f"- Account {b.account_number} — {b.currency} {b.amount_due:,.2f}" for b in candidates]
            )
            return {
                "status": "multiple_matches",
                "count": len(candidates),
                "candidates": [
                    {
                        "biller": b.biller,
                        "account_number": b.account_number,
                        "amount_due": f"{b.amount_due:.2f}",
                        "currency": b.currency,
                        "status": b.status,
                    }
                    for b in candidates
                ],
                "message": (
                    f"I found multiple {target_biller or ''} bills:\n"
                    f"{candidates_formatted}\n\n"
                    "Which one would you like to pay?"
                ),
            }

        # 6. Exactly 1 Match: Deterministic Eligibility & Amount Check
        target_bill = candidates[0]

        # Check payable status: Only UNPAID bills can be planned for payment
        if target_bill.status != "UNPAID":
            return {
                "status": "not_payable",
                "bill_status": target_bill.status,
                "message": "This bill is already paid and cannot be paid again.",
            }

        # Read amount directly from database bill record
        plan = PaymentPlan(
            bill_id=str(target_bill.id),
            biller=target_bill.biller,
            account_number=target_bill.account_number,
            amount=f"{target_bill.amount_due:.2f}",
            currency=target_bill.currency,
            bill_status=target_bill.status,
            requires_confirmation=True,
        )
        self.active_plan = plan

        return {
            "status": "plan_created",
            "bill_id": str(target_bill.id),
            "biller": target_bill.biller,
            "account_number": target_bill.account_number,
            "amount": f"{target_bill.amount_due:.2f}",
            "currency": target_bill.currency,
            "bill_status": target_bill.status,
            "requires_confirmation": True,
            "message": (
                f"I found your {target_bill.biller} bill for account {target_bill.account_number}. "
                f"Amount due: {target_bill.currency} {target_bill.amount_due:,.2f}.\n\n"
                f"Would you like to proceed with this payment?"
            ),
        }

    async def create_payment_plan(self, bill_id: str) -> Dict[str, Any]:
        """Create a proposed payment plan for a specific bill ID.

        Enforces strict ownership check, verifies status == UNPAID, and reads amount from database.
        DOES NOT execute any payment or write to the database.

        Args:
            bill_id: The UUID string of the bill.

        Returns:
            Dictionary with payment plan confirmation request or error/not_found message.
        """
        self.executed = True
        self.active_plan = None
        try:
            bill_uuid = UUID(str(bill_id).strip())
        except (ValueError, TypeError, AttributeError):
            return {"status": "error", "message": f"Invalid bill ID format: {bill_id}"}

        # Enforce user ownership via repository
        bill = await self.context.billing_service.repo.get_by_user(
            bill_uuid, self.context.authenticated_user_id
        )
        if not bill:
            return {"status": "not_found", "message": "Bill not found or does not belong to user."}

        # Eligibility check
        if bill.status != "UNPAID":
            return {
                "status": "not_payable",
                "bill_status": bill.status,
                "message": "This bill is already paid and cannot be paid again.",
            }

        plan = PaymentPlan(
            bill_id=str(bill.id),
            biller=bill.biller,
            account_number=bill.account_number,
            amount=f"{bill.amount_due:.2f}",
            currency=bill.currency,
            bill_status=bill.status,
            requires_confirmation=True,
        )
        self.active_plan = plan

        return {
            "status": "plan_created",
            "bill_id": str(bill.id),
            "biller": bill.biller,
            "account_number": bill.account_number,
            "amount": f"{bill.amount_due:.2f}",
            "currency": bill.currency,
            "bill_status": bill.status,
            "requires_confirmation": True,
            "message": (
                f"I found your {bill.biller} bill for account {bill.account_number}. "
                f"Amount due: {bill.currency} {bill.amount_due:,.2f}.\n\n"
                f"Would you like to proceed with this payment?"
            ),
        }

    def get_tools(self) -> List[Any]:
        return [self.plan_bill_payment, self.create_payment_plan]
