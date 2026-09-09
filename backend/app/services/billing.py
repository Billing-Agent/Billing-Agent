from uuid import UUID
from typing import List
from sqlalchemy.ext.asyncio import AsyncSession
from app.repositories.bill import BillRepository
from app.models.bill import Bill
from app.core.exceptions import EntityNotFoundError

class BillingService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = BillRepository(db)

    async def get_bill_by_biller_and_account(self, biller: str, account_number: str) -> Bill:
        bill = await self.repo.get_by_biller_and_account(biller, account_number)
        if not bill:
            raise EntityNotFoundError(f"Bill not found for biller {biller} and account {account_number}")
        return bill

    async def get_bill_by_id(self, bill_id: UUID) -> Bill:
        bill = await self.repo.get(bill_id)
        if not bill:
            raise EntityNotFoundError(f"Bill not found with ID {bill_id}")
        return bill

    async def get_user_bills(self, user_id: UUID) -> List[Bill]:
        return await self.repo.get_all_by_user(user_id)
