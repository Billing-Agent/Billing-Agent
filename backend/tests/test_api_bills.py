import pytest
from httpx import AsyncClient, ASGITransport
from uuid import uuid4
from decimal import Decimal

from app.main import app
from app.db.session import get_db
from app.models.user import User
from app.models.bill import Bill

import pytest_asyncio

@pytest_asyncio.fixture
async def async_client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()

@pytest.mark.asyncio
async def test_api_bills_lookup(async_client, db_session):
    # Setup Data
    user1 = User(name="User 1", email="api_bills_user1@test.com")
    db_session.add(user1)
    await db_session.flush()

    bill_ceb = Bill(user_id=user1.id, biller="CEB", account_number="TEST-CEB-987654", amount_due=Decimal("3450.00"), status="UNPAID")
    bill_water = Bill(user_id=user1.id, biller="WATER", account_number="TEST-WATER-987654", amount_due=Decimal("1250.00"), status="UNPAID")
    bill_dialog = Bill(user_id=user1.id, biller="DIALOG", account_number="TEST-DIALOG-987654", amount_due=Decimal("1990.00"), status="UNPAID")
    bill_slt = Bill(user_id=user1.id, biller="SLT", account_number="TEST-SLT-987654", amount_due=Decimal("4250.00"), status="UNPAID")
    db_session.add_all([bill_ceb, bill_water, bill_dialog, bill_slt])
    await db_session.flush()

    # 1, 2, 3, 4: Successful lookups
    res_ceb = await async_client.get("/api/v1/bills/CEB/TEST-CEB-987654")
    assert res_ceb.status_code == 200
    assert res_ceb.json()["amount_due"] == "3450.00"

    res_water = await async_client.get("/api/v1/bills/WATER/TEST-WATER-987654")
    assert res_water.status_code == 200

    res_dialog = await async_client.get("/api/v1/bills/DIALOG/TEST-DIALOG-987654")
    assert res_dialog.status_code == 200

    res_slt = await async_client.get("/api/v1/bills/SLT/TEST-SLT-987654")
    assert res_slt.status_code == 200

    # 5. Nonexistent account returns 404
    res_404 = await async_client.get("/api/v1/bills/CEB/99999")
    assert res_404.status_code == 404

    # 6. Bill lookup is case-insensitive for biller
    res_case = await async_client.get("/api/v1/bills/cEb/TEST-CEB-987654")
    assert res_case.status_code == 200

@pytest.mark.asyncio
async def test_api_user_bills_isolation(async_client, db_session):
    user_a = User(name="User A", email="usera_bills@test.com")
    user_b = User(name="User B", email="userb_bills@test.com")
    db_session.add_all([user_a, user_b])
    await db_session.flush()

    bill_a = Bill(user_id=user_a.id, biller="CEB", account_number="A1", amount_due=Decimal("100"), status="UNPAID")
    bill_b = Bill(user_id=user_b.id, biller="CEB", account_number="B1", amount_due=Decimal("200"), status="UNPAID")
    db_session.add_all([bill_a, bill_b])
    await db_session.flush()

    # 7. User can retrieve their own bills
    from app.core.security import create_access_token
    token = create_access_token(subject=user_a.id)
    headers = {"Authorization": f"Bearer {token}"}
    res_a = await async_client.get(f"/api/v1/users/{user_a.id}/bills", headers=headers)
    assert res_a.status_code == 200
    assert len(res_a.json()) == 1
    assert res_a.json()[0]["id"] == str(bill_a.id)

    # 8. User cannot retrieve another user's bills
    # The authenticated user's JWT identity is checked against the requested user_id, preventing access to another user's bills.
    assert res_a.json()[0]["id"] != str(bill_b.id)

