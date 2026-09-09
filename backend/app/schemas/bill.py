from pydantic import BaseModel, ConfigDict
from uuid import UUID
from datetime import datetime
from typing import Optional
from decimal import Decimal

class BillBase(BaseModel):
    biller: str
    account_number: str
    customer_name: Optional[str] = None
    amount_due: Decimal
    currency: str = "LKR"
    due_date: Optional[str] = None
    status: str = "UNPAID"

class BillCreate(BillBase):
    pass

class BillResponse(BillBase):
    id: UUID
    user_id: UUID
    created_at: datetime
    updated_at: datetime
    model_config = ConfigDict(from_attributes=True)
