from pydantic import BaseModel, ConfigDict
from uuid import UUID
from datetime import datetime
from typing import Optional
from decimal import Decimal

class TransactionBase(BaseModel):
    amount: Decimal
    currency: str = "LKR"
    status: str = "PENDING"
    provider: Optional[str] = None
    provider_reference: Optional[str] = None
    idempotency_key: str

class TransactionCreate(TransactionBase):
    bill_id: Optional[UUID] = None
    payment_method_id: Optional[UUID] = None

class TransactionResponse(TransactionBase):
    id: UUID
    user_id: UUID
    bill_id: Optional[UUID] = None
    payment_method_id: Optional[UUID] = None
    biller: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class PaymentPrepareRequest(BaseModel):
    bill_id: UUID
    payment_method_id: UUID
    idempotency_key: str

class PaymentPrepareResponse(BaseModel):
    transaction_id: UUID
    bill_id: UUID
    amount: Decimal
    currency: str
    status: str

