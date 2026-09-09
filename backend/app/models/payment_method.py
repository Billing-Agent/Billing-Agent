import uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy import String, Boolean, ForeignKey
from app.models.base import Base, TimestampMixin

class PaymentMethod(Base, TimestampMixin):
    __tablename__ = "payment_methods"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    provider: Mapped[str] = mapped_column(String(100), nullable=False)
    token_reference: Mapped[str] = mapped_column(String(255), nullable=False)
    card_brand: Mapped[str | None] = mapped_column(String(50), nullable=True)
    last_four: Mapped[str | None] = mapped_column(String(4), nullable=True)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False)

    user: Mapped["User"] = relationship("User", back_populates="payment_methods")
    transactions: Mapped[list["Transaction"]] = relationship("Transaction", back_populates="payment_method")
