from typing import Generic, TypeVar, Type, Optional, List, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from uuid import UUID

ModelType = TypeVar("ModelType")

class BaseRepository(Generic[ModelType]):
    def __init__(self, model: Type[ModelType], db: AsyncSession):
        self.model = model
        self.db = db

    async def get(self, id: UUID) -> Optional[ModelType]:
        result = await self.db.execute(select(self.model).filter(self.model.id == id))
        return result.scalars().first()

    async def get_by_user(self, id: UUID, user_id: UUID) -> Optional[ModelType]:
        if not hasattr(self.model, "user_id"):
            raise ValueError(f"{self.model.__name__} does not have a user_id attribute.")
        result = await self.db.execute(
            select(self.model).filter(self.model.id == id, self.model.user_id == user_id)
        )
        return result.scalars().first()
        
    async def get_all_by_user(self, user_id: UUID) -> List[ModelType]:
        if not hasattr(self.model, "user_id"):
            raise ValueError(f"{self.model.__name__} does not have a user_id attribute.")
        result = await self.db.execute(
            select(self.model).filter(self.model.user_id == user_id)
        )
        return list(result.scalars().all())

    async def create(self, obj_in: Dict[str, Any]) -> ModelType:
        db_obj = self.model(**obj_in)
        self.db.add(db_obj)
        await self.db.commit()
        await self.db.refresh(db_obj)
        return db_obj
