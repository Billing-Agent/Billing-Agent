from sqlalchemy.ext.asyncio import AsyncSession
from app.models.payment_method import PaymentMethod
from app.repositories.base import BaseRepository

class PaymentMethodRepository(BaseRepository[PaymentMethod]):
    def __init__(self, db: AsyncSession):
        super().__init__(PaymentMethod, db)
