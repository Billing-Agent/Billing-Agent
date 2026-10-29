"""
BillingAgent implementation using Google ADK and Gemini.
"""
import logging
from typing import List, Optional
from google.adk.agents import Agent
from google.adk.runners import InMemoryRunner
from google.genai import types

from app.core.config import settings
from app.core.exceptions import BusinessLogicError
from app.agent.context import BillingAgentContext
from app.agent.tools.bill_tools import BillTools
from app.agent.tools.payment_plan_tools import PaymentPlanTools
from app.agent.payment_intent import (
    AgentIntent,
    CONFIRMATION_RECEIVED_MESSAGE,
    detect_intent,
    is_confirmation_message,
)
from app.agent.prompts.system_prompt import BILLING_AGENT_SYSTEM_INSTRUCTION
from app.schemas.agent import AgentChatResponse, AgentToolCall

logger = logging.getLogger(__name__)


class BillingAgent:
    """
    Conversational Billing Agent powered by Google ADK.
    Phase 8B: Understands payment intent and prepares payment plans for confirmation.
    STRICTLY NON-EXECUTING.
    """

    def __init__(
        self,
        context: BillingAgentContext,
        model: Optional[str] = None,
        runner: Optional[InMemoryRunner] = None,
    ):
        self.context = context
        self.model = model or settings.GEMINI_MODEL

        # Check API key configuration before running
        if not settings.GEMINI_API_KEY:
            raise BusinessLogicError(
                "Gemini API key is not configured. Conversational AI agent is unavailable."
            )

        self.tools = BillTools(context)
        self.payment_plan_tools = PaymentPlanTools(context)

        all_tools = self.tools.get_tools() + self.payment_plan_tools.get_tools()

        if runner is not None:
            self.runner = runner
        else:
            self.agent = Agent(
                name="billing_agent",
                model=self.model,
                instruction=BILLING_AGENT_SYSTEM_INSTRUCTION,
                tools=all_tools,
            )
            self.runner = InMemoryRunner(agent=self.agent)

    async def chat(self, message: str) -> AgentChatResponse:
        """
        Process a user's natural language message and return the conversational response
        along with any tool calls executed, detected intent, and proposed payment plan if applicable.
        """
        if not message or not message.strip():
            raise BusinessLogicError("Message cannot be empty.")

        # Standalone confirmation phrases in Phase 8B:
        # Strictly non-executing. Do not guess a bill or execute payment.
        if is_confirmation_message(message):
            return AgentChatResponse(
                message=CONFIRMATION_RECEIVED_MESSAGE,
                intent=AgentIntent.PAY_BILL.value,
                requires_confirmation=False,
                payment_plan=None,
            )

        # Request-scoped in-memory session
        session = await self.runner.session_service.create_session(
            app_name=self.runner.app_name,
            user_id=str(self.context.authenticated_user_id),
        )

        user_content = types.Content(
            role="user",
            parts=[types.Part.from_text(text=message.strip())],
        )

        tool_calls: List[AgentToolCall] = []
        final_text = ""

        try:
            async for event in self.runner.run_async(
                user_id=str(self.context.authenticated_user_id),
                session_id=session.id,
                new_message=user_content,
            ):
                # Capture tool calls
                if event.get_function_calls():
                    for fc in event.get_function_calls():
                        tool_calls.append(
                            AgentToolCall(name=fc.name, args=dict(fc.args or {}))
                        )
                        # Ensure underlying tool executes if mock runner yielded call without running
                        if fc.name == "plan_bill_payment" and not self.payment_plan_tools.executed:
                            await self.payment_plan_tools.plan_bill_payment(**(fc.args or {}))
                        elif fc.name == "create_payment_plan" and not self.payment_plan_tools.executed:
                            await self.payment_plan_tools.create_payment_plan(**(fc.args or {}))

                # Capture model text output
                if event.is_final_response():
                    if event.content and event.content.parts:
                        for p in event.content.parts:
                            if p.text:
                                final_text += p.text
                elif event.content and event.content.parts and not event.get_function_calls():
                    for p in event.content.parts:
                        if p.text and not final_text:
                            final_text += p.text

        except Exception as e:
            logger.error("Error executing BillingAgent turn: %s", e)
            raise BusinessLogicError(
                "The billing assistant is temporarily unavailable. Please try again."
            )

        if not final_text:
            final_text = (
                "I was unable to complete your request. Please try rephrasing your question."
            )

        # Resolve intent and payment plan
        executed_tool_names = [tc.name for tc in tool_calls]
        intent = detect_intent(message, executed_tool_names)

        active_plan = self.payment_plan_tools.active_plan
        requires_confirmation = False
        payment_plan = None
        confirmation_id = None

        if active_plan is not None:
            requires_confirmation = True
            payment_plan = active_plan
            confirmation_id = self.payment_plan_tools.active_confirmation_id
            intent = AgentIntent.PAY_BILL.value

        return AgentChatResponse(
            message=final_text.strip(),
            tool_calls=tool_calls if tool_calls else None,
            intent=intent,
            requires_confirmation=requires_confirmation,
            payment_plan=payment_plan,
            confirmation_id=confirmation_id,
        )
