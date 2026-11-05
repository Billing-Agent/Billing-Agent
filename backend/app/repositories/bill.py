from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from uuid import UUID
from typing import Optional
from app.models.bill import Bill
from app.repositories.base import BaseRepository

class BillRepository(BaseRepository[Bill]):
    def __init__(self, db: AsyncSession):
        super().__init__(Bill, db)

    async def get_by_biller_and_account(self, biller: str, account_number: str, user_id: UUID) -> Optional[Bill]:
        result = await self.db.execute(
            select(self.model).filter(
                func.lower(self.model.biller) == func.lower(biller),
                self.model.account_number == account_number,
                self.model.user_id == user_id,
            )
        )
        return result.scalars().first()

    async def get_with_lock(self, bill_id: UUID) -> Optional[Bill]:
        result = await self.db.execute(
            select(self.model).filter(self.model.id == bill_id).with_for_update()
        )
        return result.scalars().first()

