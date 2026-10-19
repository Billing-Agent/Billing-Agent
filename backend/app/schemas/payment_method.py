from pydantic import BaseModel, ConfigDict
from uuid import UUID
from datetime import datetime
from typing import Optional

class PaymentMethodBase(BaseModel):
    provider: str
    card_brand: Optional[str] = None
    last_four: Optional[str] = None
    is_default: bool = False

class PaymentMethodCreate(PaymentMethodBase):
    token_reference: str

class PaymentMethodResponse(PaymentMethodBase):
    id: UUID
    user_id: UUID
    created_at: datetime
    updated_at: datetime
    model_config = ConfigDict(from_attributes=True)
