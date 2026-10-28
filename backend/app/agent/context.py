"""
Request-scoped Context for the Conversational Billing Agent.

Ensures strict user isolation and request-level scoping:
- No module-level global variables
- No mutable global user context
- authenticated_user_id is derived exclusively from the validated JWT in FastAPI dependencies
"""
from dataclasses import dataclass
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.services.billing import BillingService


@dataclass(frozen=True)
class BillingAgentContext:
    """Immutable, request-scoped context for agent execution."""
    authenticated_user_id: UUID
    db: AsyncSession
    billing_service: BillingService
