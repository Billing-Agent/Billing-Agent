import pytest
from uuid import uuid4
from decimal import Decimal
from app.models.user import User
from app.models.bill import Bill
from app.models.payment_method import PaymentMethod
from app.models.transaction import Transaction
from app.repositories.bill import BillRepository
from app.repositories.payment_method import PaymentMethodRepository
from app.repositories.transaction import TransactionRepository

@pytest.mark.asyncio
async def test_repository_user_isolation(db_session):
    # Setup: Create 2 Users
    user1 = User(name="User 1", email="user1@test.com")
    user2 = User(name="User 2", email="user2@test.com")
    db_session.add_all([user1, user2])
    await db_session.flush()

    # Setup: Create 1 Bill for User 1
    bill1 = Bill(user_id=user1.id, biller="CEB", account_number="123", amount_due=Decimal("100.50"), status="UNPAID")
    db_session.add(bill1)
    await db_session.flush()

    # Setup: Create 1 Payment Method for User 1
    pm1 = PaymentMethod(user_id=user1.id, provider="Test", token_reference="token", card_brand="Visa", last_four="1234")
    db_session.add(pm1)
    await db_session.flush()

    # Setup: Create 1 Transaction for User 1
    tx1 = Transaction(user_id=user1.id, bill_id=bill1.id, payment_method_id=pm1.id, amount=Decimal("100.50"), status="SUCCESS", idempotency_key="tx_123")
    db_session.add(tx1)
    await db_session.flush()

    # Test Bill Isolation
    bill_repo = BillRepository(db_session)
    fetched_bill_user1 = await bill_repo.get_by_user(bill1.id, user1.id)
    fetched_bill_user2 = await bill_repo.get_by_user(bill1.id, user2.id)

    assert fetched_bill_user1 is not None
    assert fetched_bill_user1.id == bill1.id
    assert fetched_bill_user2 is None

    # Test Payment Method Isolation
    pm_repo = PaymentMethodRepository(db_session)
    fetched_pm_user1 = await pm_repo.get_by_user(pm1.id, user1.id)
    fetched_pm_user2 = await pm_repo.get_by_user(pm1.id, user2.id)

    assert fetched_pm_user1 is not None
    assert fetched_pm_user2 is None

    # Test Transaction Isolation
    tx_repo = TransactionRepository(db_session)
    fetched_tx_user1 = await tx_repo.get_by_user(tx1.id, user1.id)
    fetched_tx_user2 = await tx_repo.get_by_user(tx1.id, user2.id)

    assert fetched_tx_user1 is not None
    assert fetched_tx_user2 is None
    
    # Test Precision matches Decimal
    assert fetched_tx_user1.amount == Decimal("100.50")
    
    # Ensure idempotency_key uniqueness works
    import sqlalchemy.exc
    duplicate_tx = Transaction(user_id=user1.id, bill_id=bill1.id, amount=Decimal("10.00"), status="SUCCESS", idempotency_key="tx_123")
    db_session.add(duplicate_tx)
    with pytest.raises(sqlalchemy.exc.IntegrityError):
        await db_session.flush()

    # Revert the failed flush state to continue testing
    await db_session.rollback()

    # Setup again due to rollback
    user1_new = User(name="User 1 New", email="user1new@test.com")
    db_session.add(user1_new)
    await db_session.flush()

    # Ensure email uniqueness works
    duplicate_user = User(name="Duplicate User", email="user1new@test.com")
    db_session.add(duplicate_user)
    with pytest.raises(sqlalchemy.exc.IntegrityError):
        await db_session.flush()
