"""
Pydantic schemas for the read-only conversational billing agent.
"""
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field


class AgentChatRequest(BaseModel):
    """User input message to the conversational billing assistant."""
    message: str = Field(..., min_length=1, description="User's natural language message to the assistant")


class AgentToolCall(BaseModel):
    """Metadata representing a read-only tool executed during conversation turn."""
    name: str
    args: Dict[str, Any] = Field(default_factory=dict)


class PaymentPlan(BaseModel):
    """
    Deterministic structured payment plan proposed for confirmation.
    Contains strictly verified data from the database bill record.
    """
    bill_id: str
    biller: str
    account_number: str
    amount: str
    currency: str
    bill_status: str
    requires_confirmation: bool = True


class AgentChatResponse(BaseModel):
    """Response returned to the authenticated client."""
    message: str
    tool_calls: Optional[List[AgentToolCall]] = None
    intent: Optional[str] = None
    requires_confirmation: bool = False
    payment_plan: Optional[PaymentPlan] = None
