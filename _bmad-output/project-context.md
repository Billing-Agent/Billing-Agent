# Billing Agent: verified implementation context

Verified by static source/test inspection on 2026-11-06 against commit `ddacdadc8a24d6739d9e8371ad6ee73dfe680955` on `Dev`. This is context for the existing implementation, not a redesign or a certification of runtime behavior. Paths below are repository-relative. Root `AGENTS.md` remains the policy authority and explicitly loads this reference for relevant backend/mobile/test work. No application code, dependencies, database state, or architecture was changed during this workflow.

## Authority and security boundaries

- The AI interprets intent and plans payments; it must never directly move money, invoke PayHere, change financial status, or invent amounts.
- The deterministic backend authorizes and prepares payments. PayHere supplies provider payment truth. The backend/database supply authoritative application state; Flutter SDK completion is not proof of settlement.
- Derive authenticated identity from validated JWT context. Never accept an LLM/client user ID as authority; enforce ownership server-side.
- Preserve the assistant's explicit `confirmation_id` gate. Chat text such as “yes”, “confirm”, or “go ahead” must never execute payment.
- Keep backend money as Decimal/Numeric and API/mobile amounts as strings. Preserve the existing transaction vocabulary: `PENDING`, `SUCCESS`, `FAILED`, `CANCELLED`.
- Never disclose secrets, tokens, database passwords, or `.env` contents. Current implementation exceptions are recorded below as gaps, not permissions to reproduce them.

## Backend architecture and entry points

`backend/app/main.py` builds FastAPI, mounts `/api/v1` routers, configures CORS, and maps missing entities/business errors/concurrency conflicts to 404/400/409. `backend/app/core/config.py` declares settings for JWT, Gemini, database, PayHere, and confirmation TTL. `backend/Dockerfile` selects Python 3.11; Docker Compose declares PostgreSQL 15. Backend package versions are not pinned in `backend/requirements.txt`.

Preserve the endpoint → service → repository → database boundary. The existing agent confirmation endpoint performs orchestration and some repository reads; this is current behavior, not a reason to put more database logic in endpoints. `backend/app/db/session.py` provides request-scoped async SQLAlchemy sessions over asyncpg, with explicit service commits and session close at request completion.

| Area | Source and responsibility |
| --- | --- |
| Authentication | `backend/app/api/deps.py`, `backend/app/core/security.py`, `backend/app/services/auth.py`, `backend/app/api/v1/endpoints/auth.py` |
| Bill reads | `backend/app/services/billing.py`, `backend/app/repositories/bill.py`, endpoints `bills.py`, `me.py`, `users.py` under `backend/app/api/v1/endpoints/` |
| Payment orchestration | `backend/app/services/payment.py`, `backend/app/api/v1/endpoints/payments.py` |
| Provider integration | `backend/app/services/payhere.py`, `backend/app/services/payhere_retrieval.py`, `backend/app/api/v1/endpoints/payhere.py` |
| AI and confirmation | `backend/app/agent/`, `backend/app/api/v1/endpoints/agent.py`, `backend/app/schemas/agent.py` |
| Persistence/contracts | `backend/app/models/`, `backend/app/repositories/`, `backend/app/schemas/`, `backend/alembic/` |

Core tables are users, bills, payment_methods, and transactions. Money columns are `Numeric(12, 2)`. Transaction idempotency keys are globally unique. Status columns are strings rather than database enums. Bill due dates are nullable strings in the backend.

## JWT and ownership

Registration hashes passwords with bcrypt. Login issues an access JWT; validation requires signature, expiration, `sub`, `iat`, `exp`, and `type=access`, then resolves a UUID subject to an existing active user. The configured token lifetime defaults to 60 minutes.

Agent and payment endpoints obtain identity from `get_current_user`. `/me/bills`, `/me/payment-methods`, and `/me/transactions` scope data to that user. Legacy `/users/{user_id}/...` routes compare the path ID to authenticated identity. Payment transaction lookup returns 404 for both missing and foreign-owned records. The unprotected bill-read and development endpoints are exceptions documented below.

## Google ADK, Gemini, and planning

`backend/app/agent/billing_agent.py` constructs an ADK Agent and InMemoryRunner using `GEMINI_MODEL` (default `gemini-2.5-flash`). `context.py` carries immutable request-scoped authenticated identity, DB session, and BillingService. A new ADK session is created per request; durable or multi-turn server conversation history is not implemented.

`tools/bill_tools.py` exposes owned-bill list, lookup, and search. `tools/payment_plan_tools.py` exposes `plan_bill_payment` and `create_payment_plan`. Tools normalize biller aliases, request clarification for multiple matches, require an owned UNPAID bill, and derive exact plan amount/currency from the record. Planning creates no database transaction and performs no provider call; it does create an in-memory confirmation object.

`payment_intent.py` classifies intent and intercepts standalone confirmation phrases. `prompts/system_prompt.py` instructs non-execution and factual billing responses. Prompt instructions supplement deterministic restrictions; they are not authorization. `AgentChatResponse` carries text, intent, tool metadata, a structured payment plan, `requires_confirmation`, and `confirmation_id`.

## Confirmation gate

`POST /api/v1/agent/payments/confirm` accepts only `confirmation_id` (`extra="forbid"`). `backend/app/agent/payment_confirmation.py` stores the issuing user, bill, amount, currency, expiry, consumed flag, and server-generated idempotency key. Default TTL is 300 seconds. Storage is process-local, not shared or persistent.

The endpoint checks token existence/ownership/expiry/consumption, reloads the owned bill, checks UNPAID status and matching amount/currency, requires exactly one registered payment method, and calls `PaymentService.prepare_payment()`. It marks the token consumed after preparation succeeds. It does not invoke PayHere or mark success.

The assistant follows this gate. The existing manual Flutter payment flow separately uses authenticated `POST /api/v1/payments/prepare` with bill ID, payment-method ID, and a client idempotency key. Do not describe the confirmation token as a universally enforced backend gate or silently remove/change either API contract.

## PaymentService and concurrency

`backend/app/services/payment.py` owns preparation, checkout initiation, owner-scoped transaction reads, provider callback processing, reconciliation, and the existing development success simulator.

Preparation first checks the unique idempotency key. A same-user match returns the existing transaction; another user's key is rejected. Otherwise it locks the bill using `SELECT FOR UPDATE`, verifies ownership and UNPAID status, validates payment-method ownership, and searches for an existing same-user/same-bill PENDING transaction. It reuses that pending transaction even if the new request has a different key. Only when none exists does it create and commit a new PENDING transaction using stored bill amount/currency. Integrity conflicts roll back and recheck the winning key.

`backend/app/repositories/bill.py` and `transaction.py` implement locking. The pending lookup returns the newest matching transaction. There is no partial unique database constraint for one PENDING per bill; prevention depends on this service path and bill lock. Do not bypass it or silently mutate old pending attempts.

Initiation reads an owned PENDING transaction, locks the bill, validates its owner and UNPAID status, and rejects initiation when the bill is already PAID. It does no database writes. Callback/reconciliation lock the transaction first and lock the bill for successful settlement. SUCCESS and bill PAID/zero amount commit atomically. If another transaction already settled the bill, provider success is retained on this transaction without applying bill settlement again.

## PayHere initiation and transaction lifecycle

`POST /api/v1/payments/{transaction_id}/initiate` delegates to `PayHereService.build_initiate_params()`. The pure service performs no database or outbound HTTP work. It validates required configuration and payer phone, derives order ID from transaction ID, formats the stored amount to two decimals, and signs checkout parameters server-side. Merchant signing secret is not returned in this response.

The normal assistant lifecycle is plan → explicit confirmation → PENDING transaction → initiation → SDK checkout → callback/reconciliation → terminal transaction. Successful settlement marks the associated bill PAID and sets amount due to Decimal zero. Failed/cancelled attempts leave the bill unchanged. PENDING is not cancelled merely due to age or client dismissal.

Flutter's mobile SDK adapter uses an app-specific merchant secret from `PayHereConfig`, rather than the returned web checkout hash. This is an existing credential-boundary limitation, not a guarantee that mobile credentials are secret. Sandbox defaults exist in both provider configuration and mobile checkout.

## Callback handling

`POST /api/v1/payhere/callback` is intentionally public for server-to-server delivery. It requires form encoding, parses the callback schema, and verifies the MD5 signature before database lookup. `PaymentService.process_payhere_callback()` locks the transaction and, for nonterminal records, checks configured merchant, exact Decimal amount, and currency.

| Callback code | Backend result |
| --- | --- |
| `2` | SUCCESS; atomically settle bill |
| `0` | Keep PENDING; record provider/reference |
| `-1` | CANCELLED; bill unchanged |
| `-2`, `-3` | FAILED; bill unchanged |
| Unknown | Business error; no intended mutation |

Malformed UUIDs or unknown transactions are acknowledged with an ignored result. Already-terminal transactions return without applying later callbacks. Do not casually change signature verification or substitute a client callback for provider verification.

## Reconciliation

`POST /api/v1/payments/{transaction_id}/reconcile` authenticates the owner and locks the transaction. Terminal transactions return immediately. `PayHereRetrievalClient` obtains an OAuth access token with server-side app credentials and queries the provider by order ID; the client has no DB access. Tokens are not persisted.

The service validates returned order ID/amount/currency when supplied. SUCCESS atomically settles; FAILED updates only the transaction; PENDING may update provider metadata; NOT_FOUND leaves local state unchanged. Retrieval's status normalization differs from callback mapping; keep the two contracts separate. Retrieval currently normalizes a CANCELLED item to FAILED. No mobile reconciliation request or scheduled reconciliation worker is present in inspected application source.

## Flutter architecture and Assistant

`mobile/lib/main.dart` installs ProviderScope and MaterialApp.router. `core/routing/app_router.dart` uses GoRouter with auth redirects and home/bills/transactions/settings branches, plus payment and assistant routes. `core/constants/api_config.dart` selects local emulator/loopback backend URLs. `services/api_client.dart` attaches the bearer token, applies timeouts, and maps HTTP failures. `core/storage/token_storage.dart` uses secure storage; `providers/auth_provider.dart` manages startup auth, login, logout, and unauthorized responses.

Repositories under `mobile/lib/repositories/` wrap API contracts. `repositories/providers.dart` supplies bill, payment-method, transaction, and detail queries. Models retain money strings. `services/payhere_checkout_service.dart` wraps native checkout behind an injectable interface for tests.

Home links to `screens/assistant/assistant_screen.dart`. `providers/agent_provider.dart` manages chat, structured plan cards, double-tap protection, explicit confirmation, initiation, SDK callbacks, and polling. `services/agent_service.dart` delegates to `repositories/agent_repository.dart`; confirmation sends only the opaque ID. Typing confirmation text sends chat only. Cancelling a plan is local UI state and creates no transaction or server-side token revocation.

Both the assistant and `screens/payment/payment_confirmation_screen.dart` launch checkout and poll `GET /payments/{id}` after completion/error/dismissal. They check up to three times with 1200 ms between checks; dismissal checks once. Only backend SUCCESS triggers success behavior and refreshes bills/history. The manual screen also invalidates bill details. Transaction history supports manual refresh; it is not a background reconciliation loop.

## Nullable due dates and money

`mobile/lib/models/bill.dart` declares `DateTime? dueDate` and parses a null backend due_date as null. `widgets/bill_card.dart` and `screens/bill_details/bill_details_screen.dart` render “Not available”. The constructor currently requires callers to supply the argument, but its value remains nullable; do not confuse argument presence with non-nullability. Invalid non-null date strings can still throw during parsing.

Keep amount strings through Flutter models and `core/utils/money_utils.dart`. Backend Pydantic Decimal responses serialize money as strings; PayHere initiation explicitly formats a string. Do not introduce floating-point payment calculations.

## Verification and tests

Required project commands (documented, not executed in this context-only run):

```sh
docker compose exec backend pytest -q
```

From `mobile/`:

```sh
flutter analyze
flutter test
```

Before finishing a change, from the root:

```sh
git diff --check
git status
```

Backend tests require the configured PostgreSQL database and an already-prepared schema. `backend/tests/conftest.py` normally uses savepoints and an outer rollback, but `test_concurrency_prepare_different_idempotency_keys` in `backend/tests/test_payment_pending_deduplication.py` directly commits data through AsyncSessionLocal with no cleanup. The README's blanket isolation claim does not apply to that test. Use a disposable test database for database-writing tests; do not run migrations or seed data as an implicit part of an inspection task.

Existing backend suites cover JWT/auth/ownership, agent reads/plans/non-execution, confirmation validation/reuse/expiry/changed bill facts, preparation deduplication, a five-request concurrent preparation case, initiation guards, callback signatures/status/idempotency, and reconciliation outcomes/mismatches. Key files include `test_agent.py`, `test_agent_payment_confirmation.py`, `test_payment_pending_deduplication.py`, `test_api_payhere_initiate.py`, `test_api_payhere_callback.py`, and `test_api_payhere_reconcile.py` under `backend/tests/`.

Mobile tests under `mobile/test/` cover HTTP/auth/storage/repositories/models plus login, registration, manual checkout, and Assistant widgets. `screens/assistant_screen_test.dart` verifies confirmation-only payloads, double-tap prevention, non-executing chat/cancellation, expiry/errors, provider handoff, and backend-success display. Its test named for provider refresh asserts the result dialog/amount rather than refresh counts. `screens/payment_confirmation_screen_test.dart` verifies prepare/initiate ordering and backend status authority using an injected checkout service. No explicit null-due-date test was found in the inspected suite. These are not evidence of a live native PayHere checkout passing. No tests were executed in this workflow.

## Observed inconsistencies and limits

These are static findings with source pointers, not new architecture decisions or observed agent mistakes. Reverify before implementing a separately authorized fix.

| Finding | Evidence / consequence |
| --- | --- |
| Public bill reads | `backend/app/api/v1/endpoints/bills.py` omits auth and ownership dependencies for both ID and biller/account lookup. Conflicts with ownership policy. |
| Unguarded financial simulator | `backend/app/api/v1/endpoints/dev.py` exposes unauthenticated simulate-success; `backend/app/main.py` always registers it. Violates the intended provider-only settlement boundary. |
| Confirmation check/consume race | `backend/app/api/v1/endpoints/agent.py` checks consumed before awaits, then ignores mark_consumed's return. Store locking is not atomic authorization across the request; idempotency still limits duplicate transactions. |
| Bill freshness and amount gaps | Confirmation checks bill facts before acquiring the preparation lock; bill lock queries do not force refresh of existing ORM identity-map state. Reused PENDING transactions and initiation do not compare stored transaction amount/currency with current bill facts. |
| Initiation status race | `PaymentService.initiate_payment()` reads transaction status without a transaction lock before bill locking; concurrent failure/cancellation can race. |
| Process-local tokens | `payment_confirmation.py` has no persistence, multi-worker sharing, or expired-entry cleanup. |
| Permissive retrieval validation | `payhere_retrieval.py` substitutes a requested order ID when absent and defaults successful outer responses to SUCCESS without an item status; `payment.py` permits absent amount/currency. |
| Terminal callbacks ignored | `payment.py` ignores every later callback on SUCCESS/FAILED/CANCELLED, including chargeback after success; terminal reconciliation also skips retrieval. |
| Provider I/O under lock | Reconciliation holds the transaction lock while awaiting OAuth/search HTTP operations. |
| Mobile credential exposure | `mobile/lib/core/constants/payhere_config.dart` and `models/payhere_initiate.dart` pass a configured merchant secret into the mobile SDK; the code acknowledges extractability. Backend initiation does not expose its secret. |
| Cross-account cache lifetime | `mobile/lib/providers/auth_provider.dart` logout clears auth but does not invalidate bill/history/payment-method/chat providers, which are not keyed to the authenticated user. |
| Dismissal display mismatch | Both Flutter payment callers can show CANCELLED while backend remains PENDING. Assistant cards can stay confirming after pending results or polling errors. No financial DB mutation follows from this display. |
| Assistant comment/implementation mismatch | `agent_provider.dart` claims PENDING confirmation-response validation in a comment but only checks nonempty transaction ID before calling initiation; the backend still guards initiation. |
| Incomplete onboarding | Registration does not collect phone, while initiation requires it. Settings are placeholders; manual payment selects the first method, while assistant confirmation rejects multiple methods. |
| Stateless chat vs conversational UI | Flutter retains chat messages but sends only the latest; ADK sessions are request-scoped. Follow-up clarification cannot rely on retained backend dialogue. |
| Stale documentation | README describes early phases; agent prompt says execution is not enabled although the explicit confirmation endpoint now exists. Preserve non-executing chat while distinguishing it from button-driven payment. |

## Git workflow and maintenance

`Dev` is the integration branch. Inspect status before edits, preserve unrelated work, and stop to inspect/report unexpected concurrent changes. Do not commit directly to main, use destructive Git commands, commit, or push without authorization. Avoid intentional generated Flutter edits unless required. Run diff checks/status at completion and report validation honestly.

The initial worktree was clean on `Dev`, tracking locally cached `origin/Dev` at the verified SHA; no network fetch was performed. This is provenance, not a claim about future remote state. Re-run project-context after significant implementation changes; use its record mode for actual agent mistakes. No child instruction files were created: cross-component security rules remain at the root, and the user requested both backend and mobile coverage. No hook/lint/CI changes were authorized or made; existing policies remain in prose.

## Adoption ledger

All existing sections and every independently meaningful instruction within them are retained verbatim in root AGENTS.md, outside the managed markers. There are no deletions, relocations, weakened rewrites, or automation replacements. Retain decisions are grouped below; the approval basis is the user's explicit request to generate/update the workflow context artifacts. Existing rules remain maintainer testimony even where current code does not enforce them.

| Existing section | Decision, reason, and risk if removed |
| --- | --- |
| Project Overview | Retain all: preserve intent-assistance versus money movement boundary and deterministic backend control. |
| Current Architecture / Mobile / Backend | Retain all: preserve mobile responsibilities, backend authority, layer separation, and existing-exception qualification. |
| Authentication | Retain all: preserve JWT identity and prohibitions on trusting client/LLM user IDs. |
| Billing Agent | Retain all: preserve capabilities, amount provenance, and every prohibited mutation/provider action. |
| Payment Confirmation | Retain all: preserve confirmation ID, validation list, backend preparation, and non-executing affirmative chat. |
| Payment Flow | Retain all: preserve explicit human action, initiation/settlement order, and backend authority. |
| PayHere | Retain all: preserve sandbox context, each credential restriction, signature care, and callback authority. |
| Reconciliation | Retain all: preserve retrieval behavior and prohibition on age-only cancellation. |
| Duplicate PENDING Protection | Retain all: preserve user/bill deduplication, both locking requirements, paid-bill guard, and no silent mutation. |
| Money Handling | Retain all: preserve Decimal/Numeric, API/mobile strings, and no-float rules including the stated necessity qualification. |
| Database Safety | Retain all: preserve table/status vocabulary, approval for status changes, row locking, and destructive-operation caution. |
| Flutter Bill Model | Retain all: preserve nullable due dates, null parsing, fallback display, and prohibition on requiring a non-null date. |
| Git Workflow | Retain all: preserve Dev/main constraints, before/after checks, authorization, and unrelated-work protection. |
| Parallel Agent Rules | Retain all: preserve pre-edit inspection and stop/inspect/report behavior on unexpected changes. |
| Generated Files | Retain all: preserve intentional-edit restriction, examples, and generated-change cleanup guidance. |
| Testing | Retain all: preserve backend/Flutter commands, finishing checks, and passing-suite requirement; add source-backed DB safety caveat. |
| Change Policy | Retain all ten steps: preserve smallest safe scope, contracts, focused/full relevant tests, reporting, and commit/push boundary. |
| Sensitive Files / Secrets | Retain all listed secrets and the prohibition on repeating leaked values. |
| Critical Rule | Retain all: preserve AI/backend/provider/database division of responsibility. |

The managed root addition supplies only discovery, maintenance, and verification caveats; the detailed snapshot is loaded behind an explicit path/task trigger to keep repeated instructions small. No existing policy was moved into this reference or silently retired. Refresh should retain this distinction between required policy and observed enforcement gaps.
