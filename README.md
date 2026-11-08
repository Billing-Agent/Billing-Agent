# Billing Agent

**A working mobile-first MVP for AI-assisted bill discovery and PayHere Sandbox payments.**

> **Portfolio status:** sandbox prototype / working MVP. This repository is not production-ready and must not be used for real financial activity.

Billing Agent explores how a conversational assistant can help a user understand bills and prepare a payment without giving the language model authority over money. A Flutter client provides authentication, bills, transaction history, an assistant chat, explicit payment confirmation, and PayHere Mobile SDK handoff. A FastAPI backend owns identity, bill data, payment preparation, provider verification, and financial state.

## The problem

Bill payment apps often force users to navigate provider-specific screens and manually identify the correct account and amount. Billing Agent adds a natural-language layer for questions such as “show my CEB bills” or “help me pay the overdue bill,” while keeping all payment-critical decisions in deterministic backend code.

The AI can interpret intent and propose a plan. It cannot initiate PayHere, change a bill or transaction status, choose an amount, or mark a payment successful.

## What is implemented

- Flutter authentication, bill list/detail, transaction history, manual checkout, and Billing Assistant screens
- JWT registration/login with bcrypt password hashing and secure token storage on mobile
- Owner-scoped bill, payment-method, and transaction APIs
- Google ADK + Gemini bill lookup, search, intent detection, and structured payment planning
- Backend-issued, short-lived `confirmation_id` for Assistant payment plans
- Explicit Flutter **Confirm Payment** action before deterministic preparation
- Idempotent payment preparation with bill row locking and reuse of an existing active `PENDING` transaction
- Server-signed PayHere Sandbox checkout parameters and Mobile SDK handoff
- Signature-validated PayHere callback processing and owner-authenticated Merchant Retrieval API reconciliation
- Backend-authoritative polling after checkout; Flutter SDK completion never marks a transaction `SUCCESS`
- PostgreSQL persistence, Alembic migrations, Docker Compose, backend tests, and Flutter tests

## How the system works

```mermaid
flowchart LR
    U[User] --> F[Flutter app]
    F -->|JWT API calls| B[FastAPI backend]
    B -->|Intent and read-only billing tools| A[Google ADK + Gemini]
    A --> B
    B -->|Authoritative bills and transactions| D[(PostgreSQL)]
    F -->|Explicit confirmation button| B
    B -->|Signed sandbox checkout data| F
    F -->|Mobile SDK handoff| P[PayHere Sandbox]
    P -->|Signed callback| B
    B -->|Merchant Retrieval reconciliation| P
    B -->|Verified state updates| D
```

The authority boundary is deliberate:

| Component | Responsibility |
| --- | --- |
| Flutter | User interaction, explicit consent, PayHere SDK handoff, and backend status polling |
| Google ADK / Gemini | Understand intent, read owned bill data through tools, and produce a payment proposal |
| FastAPI services | Authenticate, authorize, validate amounts, enforce idempotency and locking, and prepare payments |
| PostgreSQL | System of record for users, bills, payment methods, and transactions |
| PayHere Sandbox | Provider checkout and provider payment evidence |

## Payment flows

### Billing Assistant

1. The authenticated user sends a message to `POST /api/v1/agent/chat`.
2. Agent tools read only that user's bills and derive the exact amount and currency from PostgreSQL.
3. The backend returns a structured payment plan and opaque `confirmation_id`; no transaction or provider request is created yet.
4. The user presses **Confirm Payment**. Typing “yes,” “confirm,” or similar chat text does not execute payment.
5. `POST /api/v1/agent/payments/confirm` accepts only the confirmation ID, verifies ownership, expiry, single use, current bill facts, and the eligible payment method, then calls the deterministic payment service.
6. The backend creates or reuses a `PENDING` transaction. The client separately requests initiation and launches PayHere Sandbox.

The manual payment screen is a second intentional entry point. It uses authenticated `POST /api/v1/payments/prepare`, but still relies on backend ownership checks, stored bill amounts, idempotency, and the same initiation/provider-verification pipeline.

### Provider result and reconciliation

- `POST /api/v1/payhere/callback` is public for PayHere's server-to-server notification, but validates the callback signature before database lookup and checks merchant, amount, and currency against the stored transaction.
- A verified provider success atomically marks the transaction `SUCCESS`, marks the bill `PAID`, and sets its amount due to zero.
- Failed or cancelled provider results update the transaction and leave the bill unchanged. A pending result remains pending.
- `POST /api/v1/payments/{transaction_id}/reconcile` lets the authenticated owner query PayHere's Merchant Retrieval API through the backend.
- Checkout completion, dismissal, timeout, or a Flutter SDK callback is never accepted as proof of payment.

## Architecture and technology

| Layer | Technology |
| --- | --- |
| Mobile | Flutter, Dart, Riverpod, GoRouter, secure storage, PayHere Mobile SDK |
| API | Python 3.11, FastAPI, Pydantic |
| AI | Google Agent Development Kit, Gemini |
| Data | PostgreSQL 15, SQLAlchemy 2.x async, asyncpg, Alembic |
| Payments | PayHere Sandbox Checkout callback and Merchant Retrieval API |
| Tooling | Docker, Docker Compose, pytest, Flutter test |

The backend follows an endpoint → service → repository → database structure. Provider-specific signing and retrieval logic are isolated in PayHere services; agent tools do not receive payment-execution capabilities.

## Security controls

- Authenticated identity comes from the validated JWT, never a client or LLM-supplied `user_id`.
- Bill, payment-method, transaction, Assistant, and reconciliation operations enforce ownership server-side.
- Passwords are bcrypt-hashed; JWTs require signature, subject, issue time, expiry, and access-token type.
- Money uses PostgreSQL `NUMERIC` / Python `Decimal` and is serialized to Flutter as strings.
- Payment preparation uses idempotency keys and row locking, and reuses an existing `PENDING` attempt for the same bill.
- Backend callback-signing and Retrieval API credentials are server-side only. Raw backend secrets are not returned by initiation APIs; the separate mobile credential boundary remains a documented limitation below.
- The development success simulator is disabled by default and unavailable in production configuration. Its guarded test mode requires a disposable test database and a separate token.
- Local environment files, signing material, copied mobile packages, and generated build outputs are excluded from Git. Backend secret inputs are also excluded from its Docker build context.

## Current limitations

This is intentionally presented as an MVP, not a production payment system:

- PayHere is configured for **Sandbox** use. Provider credential scope, supported mobile credential handling, retrieval response details, and late/reversal event policy require further provider validation before real-money use.
- Assistant confirmations are stored in process memory. They are not durable across restarts or shared across multiple backend workers, and concurrent single-use authorization still needs a database-backed atomic design.
- AI conversation sessions are request-local; the Flutter UI retains messages, but the backend does not provide durable multi-turn conversation memory.
- There is no scheduled reconciliation worker. Mobile performs short status polling, while reconciliation currently requires an explicit authenticated API call.
- Seed data represents fake CEB, water, Dialog, and SLT records. The project does not integrate with real biller APIs, and the seed command does not create a public demo password.
- Mobile registration does not yet collect the phone number PayHere initiation requires. Multiple saved payment methods and account-switch cache lifecycle also need product/UI completion.
- Backend dependencies are not yet locked to a reproducible production release set.

See [`_bmad-output/planning-artifacts/technical-security-backlog.md`](_bmad-output/planning-artifacts/technical-security-backlog.md) for the detailed engineering backlog and evidence limits.

## Local setup

### Prerequisites

- Docker and Docker Compose
- Python 3.11 for a host-run backend
- Flutter SDK and an Android/iOS emulator or device
- A Gemini API key for live Assistant requests
- PayHere Sandbox merchant and Retrieval API credentials for the payment flow

### Environment configuration

Copy the public placeholder template and fill values only in the ignored `.env` file:

```bash
cp .env.example .env
```

Never commit credentials or put real values in `.env.example`. The main settings are:

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Async PostgreSQL connection URL |
| `JWT_SECRET` | Long random server-side JWT signing secret |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | Gemini access and model selection |
| `PAYHERE_MERCHANT_ID`, `PAYHERE_SECRET` | Server-side sandbox checkout/callback configuration |
| `PAYHERE_NOTIFY_URL` | Public callback URL ending in `/api/v1/payhere/callback` |
| `PAYHERE_RETURN_URL`, `PAYHERE_CANCEL_URL` | Optional client return/cancel targets |
| `PAYHERE_API_APP_ID`, `PAYHERE_API_APP_SECRET` | Server-side Merchant Retrieval API OAuth credentials |
| `PAYHERE_BASE_URL`, `PAYHERE_MERCHANT_API_BASE_URL` | Sandbox endpoints supplied by the example defaults |
| `PAYMENT_CONFIRMATION_TTL_SECONDS` | Assistant confirmation lifetime; defaults to 300 seconds |

Use placeholders when sharing configuration examples:

```dotenv
DATABASE_URL=postgresql+asyncpg://<db-user>:<db-password>@<db-host>:5432/billing_agent
JWT_SECRET=<long-random-local-value>
GEMINI_API_KEY=<gemini-api-key>
PAYHERE_MERCHANT_ID=<sandbox-merchant-id>
PAYHERE_SECRET=<server-side-sandbox-merchant-secret>
PAYHERE_NOTIFY_URL=https://<public-tunnel-host>/api/v1/payhere/callback
PAYHERE_API_APP_ID=<sandbox-retrieval-app-id>
PAYHERE_API_APP_SECRET=<sandbox-retrieval-app-secret>
```

Do not reuse the backend `PAYHERE_SECRET` as a mobile build value. Mobile credential handling remains a documented sandbox integration question, and compiled mobile constants are extractable.

### Run with Docker Compose

```bash
docker compose up --build -d
docker compose exec backend alembic upgrade head
```

The API is available at `http://localhost:8000`, with interactive documentation at `http://localhost:8000/docs`.

Optional fake development data:

```bash
docker compose exec backend python -m app.services.seed
```

The seed command creates fake records only. It does not contact billers or provide a public demo login.

### Run the backend on the host

Start PostgreSQL first, then use a host-reachable database URL (`localhost`, not the Compose service name `db`):

```bash
docker compose up -d db
cd backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/billing_agent
alembic upgrade head
uvicorn app.main:app --reload
```

Other settings are loaded from the root `.env` file.

### Run Flutter

```bash
cd mobile
flutter pub get
flutter run
```

For local development, Android Emulator uses `http://10.0.2.2:8000/api/v1`; iOS Simulator, desktop, and web use loopback. A physical device needs a local LAN backend address configured for that development session. Do not commit a personal LAN address.

PayHere checkout additionally requires a correctly registered sandbox app/package and provider-approved credentials. Do not distribute a build containing a backend callback-verification secret.

## Testing

Backend tests refuse to run without an explicit disposable PostgreSQL database named `billing_agent_test` or `billing_agent_test_<suffix>`. The schema must exist before pytest starts:

```bash
docker compose exec db createdb -U user billing_agent_test
docker compose exec \
  -e DATABASE_URL=postgresql+asyncpg://user:password@db:5432/billing_agent_test \
  backend alembic upgrade head
docker compose exec \
  -e BILLING_TEST_DATABASE_URL=postgresql+asyncpg://user:password@db:5432/billing_agent_test \
  backend pytest -q
```

Flutter checks:

```bash
cd mobile
flutter analyze
flutter test
```

The automated suites cover authentication and ownership, agent planning and non-execution, confirmation validation, payment idempotency/concurrency, PayHere initiation/callback/reconciliation contracts, repositories, models, and key Flutter screens. They use mocks for native PayHere checkout and are not evidence of a live provider transaction.

## Repository structure

```text
backend/
  app/
    agent/          # ADK agent, prompts, intent detection, and tools
    api/            # FastAPI dependencies and versioned endpoints
    core/           # Settings, JWT security, and exceptions
    models/         # SQLAlchemy models
    repositories/   # Database access
    schemas/        # API contracts
    services/       # Auth, billing, payment, PayHere, and reconciliation logic
  alembic/          # Database migrations
  tests/            # Backend unit/integration tests
mobile/
  lib/              # Flutter app, providers, repositories, screens, services, widgets
  test/             # Flutter unit and widget tests
docs/               # Project documentation
_bmad-output/       # Verified context, planning artifacts, and implementation evidence
docker-compose.yml  # Local FastAPI/PostgreSQL stack
```

## Project status and roadmap

The repository demonstrates the full sandbox path from authenticated bill discovery through explicit confirmation, checkout initiation, and provider-verified settlement. Completed hardening includes owner-scoped bill reads, a disabled-by-default development simulator, isolated database-writing tests, public-repository ignore/Docker-context protections, and maintained current-tree/history secret scanning.

The next engineering priorities are shared and atomic confirmation persistence, stricter reconciliation evidence handling, consistent payment lock ordering and stale-attempt validation, mobile account-state isolation, accurate interrupted-checkout recovery, and controlled native sandbox verification. Production use also requires provider/business decisions for late events, credential scope, user onboarding, and multiple payment methods.

## Disclaimer

Billing Agent is an educational portfolio project and sandbox prototype. It is **not for production financial use**, does not process real biller data, and does not claim production security, availability, compliance, or PayHere readiness.

## License

Released under the [MIT License](LICENSE).
