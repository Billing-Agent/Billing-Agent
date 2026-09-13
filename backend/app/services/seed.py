import asyncio
import uuid
from decimal import Decimal
from app.db.session import AsyncSessionLocal
from app.models.user import User
from app.models.bill import Bill
from app.models.payment_method import PaymentMethod
from sqlalchemy import select

async def seed_database():
    async with AsyncSessionLocal() as db:
        # Check if users already exist
        existing_user = await db.execute(select(User).limit(1))
        if existing_user.scalars().first():
            print("Database is already seeded.")
            return

        # Create Users
        # Using a deterministic UUID for user1 as the development user identity
        dev_user_id = uuid.UUID("11111111-1111-1111-1111-111111111111")
        user1 = User(id=dev_user_id, name="Alice Fake", email="alice@example.com", phone="+94771111111")
        user2 = User(name="Bob Test", email="bob@example.com", phone="+94772222222")
        user3 = User(name="Charlie Dev", email="charlie@example.com", phone="+94773333333")
        
        db.add_all([user1, user2, user3])
        await db.flush()

        # Create Bills
        bills = [
            Bill(user_id=user1.id, biller="CEB", account_number="12345", amount_due=Decimal("3450.00"), status="UNPAID"),
            Bill(user_id=user1.id, biller="CEB", account_number="12346", amount_due=Decimal("1850.00"), status="UNPAID"),
            Bill(user_id=user1.id, biller="CEB", account_number="12347", amount_due=Decimal("7200.00"), status="UNPAID"),
            Bill(user_id=user2.id, biller="WATER", account_number="50001", amount_due=Decimal("1250.00"), status="UNPAID"),
            Bill(user_id=user2.id, biller="WATER", account_number="50002", amount_due=Decimal("2450.00"), status="UNPAID"),
            Bill(user_id=user3.id, biller="DIALOG", account_number="77881", amount_due=Decimal("1990.00"), status="UNPAID"),
            Bill(user_id=user3.id, biller="DIALOG", account_number="77882", amount_due=Decimal("3450.00"), status="UNPAID"),
            Bill(user_id=user3.id, biller="SLT", account_number="90001", amount_due=Decimal("4250.00"), status="UNPAID"),
            Bill(user_id=user3.id, biller="SLT", account_number="90002", amount_due=Decimal("6100.00"), status="UNPAID"),
        ]
        db.add_all(bills)
        
        # Create Payment Methods
        pm1 = PaymentMethod(user_id=user1.id, provider="Sandbox", token_reference="sandbox_token_001", card_brand="Visa", last_four="4242")
        pm2 = PaymentMethod(user_id=user2.id, provider="Sandbox", token_reference="sandbox_token_002", card_brand="Mastercard", last_four="5555")
        
        db.add_all([pm1, pm2])
        
        await db.commit()
        print("Database seeded successfully with fake development data.")

if __name__ == "__main__":
    asyncio.run(seed_database())
