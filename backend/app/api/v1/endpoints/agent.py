"""
Agent chat endpoints.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.agent import AgentChatRequest, AgentChatResponse
from app.agent.context import BillingAgentContext
from app.agent.billing_agent import BillingAgent
from app.services.billing import BillingService

router = APIRouter()


@router.post("/chat", response_model=AgentChatResponse)
async def chat_with_billing_agent(
    request: AgentChatRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Interact with the conversational Billing Agent.
    - User authentication is strictly enforced via JWT.
    - No user_id is accepted from the client.
    - The agent operates in a strictly read-only mode scoped to current_user.id.
    """
    billing_service = BillingService(db)
    context = BillingAgentContext(
        authenticated_user_id=current_user.id,
        db=db,
        billing_service=billing_service,
    )
    agent = BillingAgent(context=context)
    return await agent.chat(request.message)
