import pytest
import pytest_asyncio
import os
import sys
from uuid import uuid4
from sqlalchemy import delete, text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

# Select the disposable database before importing app.db.session (which creates
# the application engine at import time). The normal development DB is never a
# valid test target, including for tests that use independent committed sessions.
test_database_url = os.environ.get("BILLING_TEST_DATABASE_URL")
if not test_database_url:
    raise pytest.UsageError(
        "Set BILLING_TEST_DATABASE_URL to a disposable billing_agent_test database "
        "before running backend tests. The normal billing_agent database is unsafe."
    )

try:
    target_url = make_url(test_database_url)
except Exception as exc:
    raise pytest.UsageError("BILLING_TEST_DATABASE_URL is not a valid SQLAlchemy URL.") from exc

test_database_name = target_url.database or ""
if (
    target_url.drivername != "postgresql+asyncpg"
    or not (
        test_database_name == "billing_agent_test"
        or test_database_name.startswith("billing_agent_test_")
    )
):
    raise pytest.UsageError(
        "Backend tests require a PostgreSQL/asyncpg database named "
        "billing_agent_test or billing_agent_test_<suffix>."
    )

if "app.core.config" in sys.modules or "app.db.session" in sys.modules:
    raise pytest.UsageError(
        "Application settings/session were loaded before the test database guard."
    )

os.environ["DATABASE_URL"] = test_database_url

from app.core.config import settings
from app.db.session import AsyncSessionLocal, engine as test_engine
from app.models.bill import Bill
from app.models.payment_method import PaymentMethod
from app.models.transaction import Transaction
from app.models.user import User

if make_url(settings.DATABASE_URL) != target_url or test_engine.url != target_url:
    raise pytest.UsageError("Fixture and application engines must use the same test database.")

@pytest_asyncio.fixture(scope="session", autouse=True)
async def setup_test_schema():
    # Schema must already exist; never create it implicitly during a test run.
    try:
        async with test_engine.connect() as conn:
            actual_database = await conn.scalar(text("SELECT current_database()"))
            if actual_database != test_database_name:
                raise pytest.UsageError(
                    "Connected database does not match BILLING_TEST_DATABASE_URL."
                )
        yield
    finally:
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
        try:
            async with async_session_maker() as session:
                yield session
        finally:
            await transaction.rollback()


@pytest_asyncio.fixture
async def committed_concurrency_user_id():
    """Clean independent-session test rows even when a test assertion fails."""
    user_id = uuid4()
    try:
        yield user_id
    finally:
        async with AsyncSessionLocal() as session:
            await session.execute(delete(Transaction).where(Transaction.user_id == user_id))
            await session.execute(delete(PaymentMethod).where(PaymentMethod.user_id == user_id))
            await session.execute(delete(Bill).where(Bill.user_id == user_id))
            await session.execute(delete(User).where(User.id == user_id))
            await session.commit()
