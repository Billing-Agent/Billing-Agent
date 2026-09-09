from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from uuid import UUID
from typing import Optional
from app.models.transaction import Transaction
from app.repositories.base import BaseRepository

class TransactionRepository(BaseRepository[Transaction]):
    def __init__(self, db: AsyncSession):
        super().__init__(Transaction, db)

    async def get_by_idempotency_key(self, key: str) -> Optional[Transaction]:
        result = await self.db.execute(
            select(self.model).filter(self.model.idempotency_key == key)
        )
        return result.scalars().first()

    async def get_with_lock(self, transaction_id: UUID) -> Optional[Transaction]:
        result = await self.db.execute(
            select(self.model).filter(self.model.id == transaction_id).with_for_update()
        )
        return result.scalars().first()

