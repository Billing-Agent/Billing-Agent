import pytest
import pytest_asyncio
import os
import sys
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.config import settings
from app.models.base import Base

# Ensure the tests use localhost if running locally on the host
db_url = settings.DATABASE_URL
if not os.path.exists("/.dockerenv") and "db:5432" in db_url:
    db_url = db_url.replace("db:5432", "localhost:5432")
    settings.DATABASE_URL = db_url

test_engine = create_async_engine(db_url, echo=False)

@pytest_asyncio.fixture(scope="session", autouse=True)
async def setup_test_schema():
    # Tables are created by Alembic before tests run.
    yield
    await test_engine.dispose()

@pytest_asyncio.fixture
async def db_session():
    async with test_engine.connect() as conn:
        transaction = await conn.begin()
        async_session_maker = async_sessionmaker(
            bind=conn, 
            class_=AsyncSession, 
            expire_on_commit=False,
            join_transaction_mode="create_savepoint"
        )
        async with async_session_maker() as session:
            yield session
        await transaction.rollback()
