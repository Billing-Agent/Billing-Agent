# Billing Agent

A real-world, production-oriented mobile AI financial/payment agent.

## Technology Stack
- **Mobile**: Flutter
- **Backend**: Python, FastAPI, SQLAlchemy 2.x (Async)
- **Database**: PostgreSQL 15, Alembic Migrations
- **AI**: Google Agent Development Kit (ADK), Gemini
- **Payments**: PayHere
- **Infrastructure**: Docker, Docker Compose

## Project Structure
- `/backend`: FastAPI Python application.
- `/mobile`: Flutter mobile application.
- `/docs`: Documentation and specifications.
- `/tests`: Integration and end-to-end testing.

## Phase 1 & 2 Implementation
This phase establishes a clean, secure, scalable project foundation and database architecture.
The database schema uses async SQLAlchemy 2.0 with isolated repository patterns for:
- `Users`
- `Bills`
- `Payment Methods`
- `Transactions`

## Setup Instructions

### 1. Environment Configuration
Copy the `.env.example` file to create your local `.env`:
```bash
cp .env.example .env
```
*(Note: Do not commit `.env` to version control, and do not place real secrets in `.env.example`)*

### 2. Starting PostgreSQL Infrastructure
Start the PostgreSQL container in the background using Docker Compose:
```bash
docker compose up db -d
```
The database will be available at `localhost:5432` with credentials defined in your `.env`.

### 3. Database Migrations (Alembic)
Ensure your Python virtual environment is activated. Run Alembic migrations to create the database schema:
```bash
cd backend
source .venv/bin/activate
# Depending on whether you are running inside or outside docker, export the correct URL
export DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/billing_agent
alembic upgrade head
```

### 4. Seeding Development Data
To seed the database with **FAKE DEVELOPMENT DATA ONLY** (Fake Users, Bills, Payment Methods):
```bash
cd backend
export DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/billing_agent
python -m app.services.seed
```
*Warning: This populates fake accounts for testing. It does not connect to real CEB, SLT, or Dialog APIs.*

### 5. Running the Test Suite
Backend tests require a separate, disposable PostgreSQL database with its schema already prepared. Set `BILLING_TEST_DATABASE_URL` to a database named `billing_agent_test` or `billing_agent_test_<suffix>`; the test guard rejects the normal `billing_agent` database. Most tests use rollback-isolated savepoints, but two payment concurrency tests use independent committed sessions to exercise real locking. Those tests remove their own rows during teardown, including after failures. Do not run the suite against development data.
```bash
cd backend
export BILLING_TEST_DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/billing_agent_test
pytest -v
```
The test runner uses this URL for both the fixture engine and application sessions. It does not create the database or run migrations. When running inside Compose, verify that the disposable database exists and has the expected schema, then pass its container-reachable URL explicitly:
```bash
docker compose exec -e BILLING_TEST_DATABASE_URL=postgresql+asyncpg://user:password@db:5432/billing_agent_test backend pytest -q
```

### 6. Running FastAPI Locally
```bash
cd backend
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```
The API will be available at http://localhost:8000.
