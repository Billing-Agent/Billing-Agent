# Billing Agent - Project Rules

## Project Overview

This is a mobile-first AI-powered bill payment agent.

Main user flow:

Flutter Mobile App
→ FastAPI Backend
→ Google ADK + Gemini
→ Deterministic Backend Tools
→ PostgreSQL
→ PayHere Sandbox

The AI is responsible for understanding user intent and assisting with bill/payment workflows.

The AI must NEVER directly move money.

All payment-critical actions must remain deterministic and backend-controlled.

---

## Current Architecture

### Mobile

Flutter

Important packages:
- flutter_riverpod
- go_router
- payhere_mobilesdk_flutter

Mobile responsibilities:
- authentication UI
- bills UI
- Billing Assistant chat UI
- payment confirmation UI
- PayHere SDK handoff
- transaction status polling

Flutter must NEVER directly mark a transaction SUCCESS.

Backend transaction state is authoritative.

---

### Backend

FastAPI
Python 3.11
SQLAlchemy 2.x async
asyncpg
PostgreSQL 15
Alembic

Main layers:

backend/app/api/
backend/app/core/
backend/app/db/
backend/app/models/
backend/app/repositories/
backend/app/schemas/
backend/app/services/
backend/app/agent/

Keep these layers separated.

Do not place database logic directly inside API endpoints unless already part of the existing architecture.

Prefer:

API
→ Service
→ Repository
→ Database

---

## Authentication

JWT authentication is implemented.

Authenticated user identity must always come from backend JWT context.

Never trust:

user_id from client
user_id from LLM
user_id from Flutter request body

Ownership checks must always be enforced server-side.

---

## Billing Agent

Google ADK + Gemini are integrated.

Agent endpoint:

POST /api/v1/agent/chat

Agent capabilities currently include:

- viewing bills
- finding bills
- understanding bill payment intent
- producing payment plans
- requesting explicit payment confirmation

The agent must NEVER:

- directly change bill status
- directly change transaction status
- directly call PayHere
- directly mark payment SUCCESS
- invent bill amounts
- bypass ownership rules

Amounts must come from backend/database records.

---

## Payment Confirmation

Payment planning returns a backend-issued confirmation_id.

Actual preparation occurs through:

POST /api/v1/agent/payments/confirm

This endpoint:

- requires JWT
- accepts only confirmation_id
- validates ownership
- validates expiration
- validates single use
- re-checks bill status
- re-checks amount
- re-checks currency
- uses server-generated idempotency
- then calls existing PaymentService.prepare_payment()

Never bypass this confirmation gate.

Text such as:

"yes"
"confirm"
"go ahead"

must not directly execute payment.

---

## Payment Flow

Current payment lifecycle:

Payment Plan
→ confirmation_id
→ explicit Flutter Confirm Payment button
→ backend confirmation endpoint
→ PENDING transaction
→ backend payment initiation
→ PayHere SDK
→ PayHere callback / reconciliation
→ backend SUCCESS
→ bill PAID

Backend is always source of truth.

---

## PayHere

PayHere Sandbox is currently used.

Important rules:

- Never expose PayHere credentials
- Never commit secrets
- Never print Merchant Secret
- Never print API App Secret
- Never modify callback signature validation casually
- Never mark SUCCESS based only on Flutter SDK completion callback

PayHere callback and reconciliation determine provider truth.

---

## Reconciliation

PayHere Merchant Retrieval API is integrated.

Existing reconciliation logic is important.

Do not automatically cancel PENDING transactions based only on age.

Provider state must remain authoritative.

---

## Duplicate PENDING Protection

The project prevents multiple active PENDING transactions for the same bill.

Current intended behavior:

same user
+
same bill
+
existing PENDING transaction

→ reuse existing PENDING transaction

Do not create another one.

Payment preparation uses bill row locking.

Payment initiation also re-checks and locks the bill.

If bill is already PAID:

old PENDING transaction must not be initiated.

Do not silently mutate old PENDING transactions.

---

## Money Handling

Never use floating point for money.

Backend:
Decimal / Numeric

API:
money serialized as string

Flutter:
keep money as String where possible

Example:

"7200.00"

Do not convert financial amounts to double unless absolutely necessary.

---

## Database Safety

Current core tables include:

users
bills
payment_methods
transactions

Transactions use:

PENDING
SUCCESS
FAILED
CANCELLED

Do not invent new statuses without explicit architectural approval.

Use row locking for payment-critical concurrency.

Avoid destructive database operations.

---

## Flutter Bill Model

Bill.dueDate is intentionally nullable:

DateTime? dueDate

Backend may return:

due_date = null

Correct parsing:

dueDate: map['due_date'] != null
    ? DateTime.parse(map['due_date'] as String)
    : null

UI must show:

"Not available"

when dueDate is null.

Do NOT make dueDate required.

---

## Git Workflow

Integration branch:

Dev

Do NOT commit directly to main.

Before editing:

git status

Before finishing:

git diff --check
git status

Do not commit or push unless explicitly requested.

Do not use destructive Git commands.

Do not reset unrelated user work.

---

## Parallel Agent Rules

This project may be edited by:

- Antigravity
- Codex extension
- Codex workspace
- human developer

Before changing files:

1. inspect git status
2. inspect relevant files
3. understand existing implementation
4. avoid files currently being modified by another agent

Do not overwrite newer on-disk changes with stale editor buffers.

If a file changes unexpectedly while working:

STOP
inspect diff
report conflict
do not overwrite blindly

---

## Generated Files

Do not intentionally modify generated Flutter files unless required.

Examples:

mobile/linux/flutter/generated_plugins.cmake
mobile/windows/flutter/generated_plugins.cmake

Generated changes should usually be reverted before committing.

---

## Testing

Backend:

docker compose exec backend pytest -q

Flutter:

cd mobile
flutter analyze
flutter test

Before completion:

git diff --check
git status

All existing tests must remain passing.

---

## Change Policy

For every task:

1. inspect existing implementation first
2. identify smallest safe change
3. avoid unrelated refactors
4. preserve API contracts unless explicitly changing them
5. preserve security boundaries
6. add/update focused tests
7. run full relevant test suites
8. report files changed
9. report test results
10. stop before commit/push unless explicitly asked

---

## Sensitive Files / Secrets

Never expose or commit:

.env
JWT tokens
GEMINI_API_KEY
PAYHERE_SECRET
PAYHERE_API_APP_SECRET
PayHere Merchant Secret
database passwords

If a secret appears in logs or prompts, do not repeat it.

---

## Critical Rule

The LLM assists with decisions.

The backend authorizes payments.

PayHere confirms provider payment state.

The database is the system of record.