# Billing Agent technical and security backlog

Planning artifact · 2026-11-06 · existing `Dev` implementation at `279f0db1625ad355054ead8127e9746b602fa9b1` · static review only

Source of truth: `AGENTS.md`, `_bmad-output/project-context.md`, current backend/mobile source, tests, and Git state. This backlog proposes fixes within the existing Flutter → FastAPI → ADK/Gemini → deterministic services → PostgreSQL → PayHere sandbox structure. A priority is a planning judgment, not evidence that a provider behavior is confirmed. The four categories describe scheduling; “Accepted prototype limitation” is a proposed disposition for the present prototype, not a production risk waiver.

Guardrails: AI never moves money or sets bill/transaction status. Backend JWT identity, bill ownership, Decimal amounts, idempotency, and the explicit Assistant `confirmation_id` gate remain in force. Provider callback/reconciliation evidence determines settlement; Flutter completion/dismissal is never financial truth. Keep current transaction statuses and do not auto-cancel PENDING based on age. Do not silently mutate old PENDING attempts.

## Counts and release boundary

| Category | Items |
| --- | ---: |
| Critical before production | 10 |
| High priority / next development phase | 8 |
| Accepted prototype limitation | 4 |
| Nice-to-have improvement | 4 |

Items B01–B10 block real-money production as written. B06/B07 specifically block multi-worker confirmation readiness. B12 must precede any backend database-writing test run against a valuable database. B03, B05, B10, B16/B17, and B20 contain explicit manual/provider/product decisions; their recommended directions do not authorize an unverified PayHere contract or an API redesign. High-priority B11–B18 should be closed or have a documented operational constraint before a public release.

## Suggested implementation sequence

0. **Make verification safe:** B12 isolates both concurrency tests before running the backend suite. Correct the test-safety wording in B23 at the same time.
1. **Close exposed boundaries:** B01 removes production simulator access, B02 scopes bill reads, B04 clears cross-account mobile state. Begin B03 credential verification in parallel.
2. **Establish provider truth:** manually verify PayHere retrieval and event contracts (M1–M3), then implement B05. Resolve B10 from verified event semantics; do not invent chargeback transitions.
3. **Harden payment concurrency:** agree a consistent lock order (B09), validate current facts/stale attempts (B08), implement shared confirmation state (B06), then atomic single-use authorization (B07). Add focused concurrent tests with each step.
4. **Restore and present outcomes accurately:** B11 shortens DB lock lifetime; B13/B14 correct payment UI state; B15 adds bounded reconciliation recovery after B05/B10/B11.
5. **Finish user paths and release evidence:** B16 phone onboarding, B17 method policy, B18 consumer/provider/worker verification. Reassess B19–B22 and address B23–B26 as the prototype matures.

## Manual verification gates

- **M1 — credential scope and mobile checkout:** Confirm with the actual PayHere merchant configuration and authoritative provider material whether the app-specific mobile credential can authenticate callbacks or has different scope; review restrictions and rotation path. Use sanitized evidence only. Also verify supported SDK checkout fields/platform builds. Blocks B03 and informs B17.
- **M2 — retrieval contract:** Capture sanitized sandbox search responses covering found, pending, failed/cancelled, multiple records, missing fields, and HTTP 404. Confirm which field is a request-level status versus a payment status and which identity/amount/currency fields are guaranteed. Blocks final B05 parsing/mapping decisions.
- **M3 — late events and reversals:** Verify PayHere callback/retrieval ordering, duplicates, chargeback meaning, and whether a terminal local result can later change at the provider. Decide how discrepancies are recorded/escalated without new statuses or automatic bill reversals. Blocks B10 and informs B11/B15.
- **M4 — deployment topology:** Confirm planned worker count, restart behavior, database availability, and expiry/retention requirements. Single-process sandbox is the only configuration the current in-memory token store can reliably support. Blocks B06/B07 acceptance.
- **M5 — bill and pending-attempt lifecycle:** Verify whether bill amount/currency can change while an attempt is PENDING, examine any existing duplicate PENDING data read-only before considering a constraint, and agree an explicit recovery path for stale attempts. Informs B08/B09/B21; do not cancel or overwrite provider attempts by assumption.
- **M6 — product/API contracts:** Confirm whether confirmation_id is scoped to Assistant only, how multiple saved methods are meant to work with PayHere SDK checkout, whether existing accounts need phone completion, and accepted non-null bill date format. Informs B16/B17/B20/B24; maintain existing APIs until decided.

## Backlog

### Critical before production

#### B01 — Disable the unauthenticated payment simulator

- **Issue and why it matters:** The development route is always mounted and can settle a known pending transaction without authentication or PayHere evidence.
- **Affected files/components:** `backend/app/main.py`; `backend/app/api/v1/endpoints/dev.py`; `backend/app/services/payment.py (simulate_success)`; `backend/tests/test_api_payments.py`.
- **Security/reliability impact:** Financial integrity: synthetic SUCCESS and PAID records can replace provider truth.
- **Recommended fix direction:** Make simulation absent in production and disabled by default. Keep any needed test/development simulation in an explicit isolated environment; merely requiring a normal user JWT is insufficient.
- **Architecture change:** No: deployment/API exposure hardening within existing layers.
- **Dependencies:** B12 for safe DB-backed verification; no code prerequisite.
- **Suggested implementation order:** 01.
- **Suggested tests:** Assert route is unavailable under production/default configuration, no unauthenticated or normal-user mutation, explicit test-mode simulation remains isolated, and real signed callback settlement still works.
- **Can it safely wait?** No for any exposed deployment; immediately contain access. Sandbox is not justification for public mutation.

#### B02 — Enforce ownership on both bill-read endpoints

- **Issue and why it matters:** ID and biller/account endpoints query bills without JWT or user filtering; returned records expose account and customer data.
- **Affected files/components:** `backend/app/api/v1/endpoints/bills.py`; `backend/app/services/billing.py`; `backend/app/repositories/bill.py`; `backend/tests/test_api_bills.py`; `mobile/lib/repositories/bill_repository.dart`.
- **Security/reliability impact:** Confidentiality: unauthenticated and cross-user billing disclosure.
- **Recommended fix direction:** Require get_current_user and owner-scoped repository predicates for both lookups. Preserve response shape and use consistent missing/foreign-owner responses; do not trust a supplied user_id.
- **Architecture change:** No: fills a missing existing security boundary.
- **Dependencies:** B12 for safe tests.
- **Suggested implementation order:** 02.
- **Suggested tests:** Anonymous 401; user A cannot read B by UUID or biller/account; owner succeeds; case normalization remains correct; mobile detail lookup still works.
- **Can it safely wait?** No before public access.

#### B03 — Verify and secure the mobile PayHere credential boundary

- **Issue and why it matters:** The mobile SDK receives an embedded merchant_secret, while callbacks trust a backend signing secret. Extractability is confirmed; credential equivalence and forgery capability are not.
- **Affected files/components:** `mobile/lib/core/constants/payhere_config.dart`; `mobile/lib/models/payhere_initiate.dart`; `mobile/lib/services/payhere_checkout_service.dart`; `backend/app/services/payhere.py`.
- **Security/reliability impact:** Potential financial integrity failure if an extractable credential can authenticate backend callbacks; actual scope must be established.
- **Recommended fix direction:** Manually verify app-specific credential capabilities, restrictions, and relationship to callback signing credentials without displaying values. If signing authority is exposed, select a provider-supported secure checkout boundary and assess rotation. Never assume obfuscation, compile-time injection, or backend field checks protect a compromised signing key.
- **Architecture change:** Conditional: a supported checkout-boundary change may be required; do not choose or implement one in this plan.
- **Dependencies:** Manual verification M1; B18 for subsequent sandbox validation.
- **Suggested implementation order:** 03 (start investigation alongside 01).
- **Suggested tests:** Sanitized credential-scope evidence; release artifact secret-boundary checks; wrong-key callbacks rejected; real supported native checkout and provider verification on a controlled sandbox build.
- **Can it safely wait?** No unresolved credential-boundary question may cross into real-money production. Restricted sandbox-only experimentation can continue.

#### B04 — Isolate Flutter state across account transitions

- **Issue and why it matters:** Logout clears auth but not persistent bill/history/payment-method/chat providers. An old request or SDK callback may also complete after a new login.
- **Affected files/components:** `mobile/lib/providers/auth_provider.dart`; `mobile/lib/providers/agent_provider.dart`; `mobile/lib/repositories/providers.dart`; `mobile/lib/services/api_client.dart`.
- **Security/reliability impact:** Confidentiality and reliability: account B may see account A data or late payment UI results.
- **Recommended fix direction:** Bind account-owned providers to identity/session, dispose or invalidate on logout/account change, and ignore late async results from superseded sessions. Retain backend ownership checks.
- **Architecture change:** No: Riverpod lifecycle correction.
- **Dependencies:** None; coordinate B14 and B18.
- **Suggested implementation order:** 04.
- **Suggested tests:** Warm all user-A caches and chat, logout/login as B, assert no A data; complete delayed A requests/checkout callbacks after B login; test expired-token logout and same-user relogin.
- **Can it safely wait?** No before shared-device or multi-account production use.

#### B05 — Require complete, unambiguous reconciliation evidence

- **Issue and why it matters:** Retrieval substitutes missing order IDs, allows missing amount/currency, defaults outer success to payment success, selects the first list record, and maps CANCELLED to FAILED.
- **Affected files/components:** `backend/app/services/payhere_retrieval.py (_parse_search_response)`; `backend/app/schemas/payhere.py`; `backend/app/services/payment.py (reconcile_pending_transaction)`; `backend/tests/test_api_payhere_reconcile.py`.
- **Security/reliability impact:** Financial integrity: API request success or ambiguous/incomplete evidence can become bill settlement; terminal outcome mapping can diverge.
- **Recommended fix direction:** First verify the provider contract and sanitized responses. Select an explicit matching payment record; require verified identity, finite exact amount, currency and actual payment status before settlement. Reject incomplete/ambiguous evidence without changing financial state. Establish documented retrieval mappings independently of callback codes.
- **Architecture change:** No for strict parsing/validation; any status-contract change requires explicit approval and existing vocabulary.
- **Dependencies:** Manual verification M2; B12 for tests. Required before B11/B15.
- **Suggested implementation order:** 05.
- **Suggested tests:** Missing/null/blank order, amount, currency, status; outer success without payment evidence; multiple/unrelated records; mismatches; malformed/non-finite amount; cancellation mapping; provider HTTP/API failures; valid response settles once; NOT_FOUND stays PENDING.
- **Can it safely wait?** No before relying on reconciliation in production.

#### B06 — Make confirmation storage shared, durable, and bounded

- **Issue and why it matters:** Process-local tokens cannot be resolved by another worker, disappear on restart, and accumulate after expiry.
- **Affected files/components:** `backend/app/agent/payment_confirmation.py`; `backend/app/agent/tools/payment_plan_tools.py`; `backend/app/api/v1/endpoints/agent.py`; `backend/app/core/config.py`; `backend/app/db/session.py`.
- **Security/reliability impact:** Availability and authorization consistency: valid confirmations randomly fail across workers and consumption cannot be coordinated globally.
- **Recommended fix direction:** Replace the dictionary with shared durable confirmation persistence, preferably evaluate existing PostgreSQL to keep preparation and consumption atomic. Preserve opaque token-only requests, owner binding, TTL, server idempotency, and bounded retention. Specify failure/retry semantics; sticky routing is not a sufficient fix.
- **Architecture change:** Yes, bounded internal persistence change; may require a later approved migration. No external service is mandated.
- **Dependencies:** B09 lock-order decision; coordinate B07. Manual verification M4.
- **Suggested implementation order:** 08.
- **Suggested tests:** Issue in worker A/confirm in B; restart after issue and after commit; cross-worker duplicate consume; expiry boundary; unavailable store fails closed; cleanup never invalidates active authorization or destroys needed retry evidence.
- **Can it safely wait?** Can remain single-process sandbox only with explicit restart/expiry limits; blocks multi-worker and production confirmation readiness.

#### B07 — Atomically consume confirmation with preparation

- **Issue and why it matters:** Consumed is checked before awaits, then marked after preparation; mark_consumed's result is ignored. Existing transaction idempotency does not enforce single-use authorization.
- **Affected files/components:** `backend/app/api/v1/endpoints/agent.py`; `backend/app/agent/payment_confirmation.py`; `backend/app/services/payment.py`; `backend/tests/test_agent_payment_confirmation.py`.
- **Security/reliability impact:** Authorization/reliability: concurrent confirmations both pass, and commit/response loss has ambiguous recovery.
- **Recommended fix direction:** Use a deterministic service operation that locks/claims the confirmation and validates/prepares within a coordinated transaction boundary. Commit consumption only with successful preparation; define retries after failure or lost response without granting a second authorization. Preserve single-use and server-generated idempotency.
- **Architecture change:** Yes, bounded transaction orchestration change coordinated with B06; no AI/payment-provider authority change.
- **Dependencies:** B06, B08, B09; B12 for concurrency tests.
- **Suggested implementation order:** 09.
- **Suggested tests:** Barrier-synchronized same-token requests across sessions/workers; exactly one authorized transition and one transaction; rollback before prepare; crash/lost response after commit; expiry during lock wait; wrong-user race; duplicate retry policy.
- **Can it safely wait?** No for production; do not claim the current threading lock solves request-level atomicity.

#### B08 — Revalidate financial facts under locks and reject stale attempts

- **Issue and why it matters:** Confirmation checks bill facts before locking; ORM identity-map values can remain stale. Pending reuse and initiation do not compare transaction amount/currency with current confirmed facts.
- **Affected files/components:** `backend/app/api/v1/endpoints/agent.py`; `backend/app/services/payment.py`; `backend/app/repositories/bill.py`; `backend/app/repositories/transaction.py`.
- **Security/reliability impact:** Financial integrity: stale status, amount, or currency can be used despite a newer explicit plan.
- **Recommended fix direction:** Freshly load locked bill state and compare owner/status/amount/currency to trusted confirmation facts before prepare. Validate reused attempt compatibility and initiation amount/currency. Reject mismatch with explicit recovery; do not rewrite/cancel an old PENDING attempt or create another active one to escape the conflict.
- **Architecture change:** No architectural redesign; existing service transaction boundary must be strengthened.
- **Dependencies:** B09 lock order; coordinate B07 and manual resolution M5.
- **Suggested implementation order:** 07.
- **Suggested tests:** Change bill amount/currency/status between initial read and lock; preloaded ORM entity; pending with old amount/currency; same-bill concurrent requests; same idempotency key replay. Assert mismatch causes no mutation or duplicate attempt.
- **Can it safely wait?** No before real payments.

#### B09 — Close initiation status races with a consistent lock protocol

- **Issue and why it matters:** Initiation reads PENDING before bill locking without locking/rechecking the transaction; failure/cancellation can race while it waits.
- **Affected files/components:** `backend/app/services/payment.py (prepare/initiate/callback/reconcile)`; `backend/app/repositories/bill.py`; `backend/app/repositories/transaction.py`.
- **Security/reliability impact:** Financial integrity/reliability: stale checkout parameters can be emitted for an already-terminal transaction; naive extra locks can deadlock.
- **Recommended fix direction:** Define one compatible lock acquisition/revalidation protocol across all payment paths, including preparation that currently starts from the bill. Freshly verify transaction and bill immediately before parameter generation. Do not simply add a bill-then-transaction lock opposite callback order. Preserve guards and idempotency.
- **Architecture change:** No: transaction-concurrency hardening inside current architecture.
- **Dependencies:** B12 for tests; M5 for transaction/lock behavior. Provider replay semantics remain M1/M3.
- **Suggested implementation order:** 06.
- **Suggested tests:** Initiate racing FAILED/CANCELLED/SUCCESS callbacks; paid bill while waiting; prepare versus callback/reconcile lock contention; bounded completion/no deadlocks; unchanged initiation produces no financial writes.
- **Can it safely wait?** No before real payments. Locks only protect generation; they cannot revoke already-delivered checkout parameters or lock the provider.

#### B10 — Define safe handling of later provider evidence on terminal transactions

- **Issue and why it matters:** Terminal callbacks and reconciliation return immediately, so later disagreement—including chargeback or late success—is ignored as if it were a duplicate.
- **Affected files/components:** `backend/app/services/payment.py`; `backend/app/services/payhere.py`; `backend/tests/test_api_payhere_callback.py (terminal tests)`; `backend/tests/test_api_payhere_reconcile.py`.
- **Security/reliability impact:** Financial correctness: backend records can diverge from genuine later provider evidence.
- **Recommended fix direction:** Verify event ordering and reversal semantics, then define an explicit permitted transition/discrepancy policy. Distinguish identical replay from a new event; validate evidence and record/escalate unresolved disagreement. Do not blindly flip SUCCESS, reopen a paid bill, invent transaction statuses, or automate refunds.
- **Architecture change:** Conditional: event evidence/audit persistence may be needed; any lifecycle extension requires approval.
- **Dependencies:** M3 business/provider policy; B05 strict evidence; B09 locking.
- **Suggested implementation order:** 10 (contract investigation starts early).
- **Suggested tests:** Duplicate delivery; CANCELLED/FAILED then verified late SUCCESS; SUCCESS then -3; out-of-order repeated events; no double bill settlement; unsupported transitions preserve financial records and surface discrepancy.
- **Can it safely wait?** No unresolved policy before real-money production; current behavior may remain only in controlled sandbox.


### High priority / next development phase

#### B11 — Keep provider network waits outside database critical sections

- **Issue and why it matters:** Reconciliation holds a transaction row lock through OAuth and search calls.
- **Affected files/components:** `backend/app/services/payment.py (reconcile_pending_transaction)`; `backend/app/services/payhere_retrieval.py`; `backend/app/db/session.py`.
- **Security/reliability impact:** Availability: delayed provider calls block callbacks and tie up connections.
- **Recommended fix direction:** Authorize/read a snapshot, release the transaction/connection as appropriate, retrieve evidence, then acquire locks and freshly revalidate ownership/current state before applying atomically. If a callback wins, follow B10 policy; stale retrieval must not overwrite newer truth. Retain bounded timeouts.
- **Architecture change:** No: service transaction-boundary adjustment.
- **Dependencies:** B05, B09, B10.
- **Suggested implementation order:** 11.
- **Suggested tests:** Slow/timeout retrieval with concurrent callback; callback commits without waiting on network; two reconciles; terminal state reached mid-fetch; provider failure leaves DB unchanged; connection/lock duration check.
- **Can it safely wait?** May wait in low-traffic sandbox; resolve before meaningful concurrent production traffic.

#### B12 — Isolate both database-writing concurrency tests

- **Issue and why it matters:** The usual savepoint fixture does not cover independent committed AsyncSessionLocal sessions in two tests; README overstates rollback isolation.
- **Affected files/components:** `backend/tests/conftest.py`; `backend/tests/test_payment_pending_deduplication.py:395`; `backend/tests/test_api_payments.py:207`; `README.md`.
- **Security/reliability impact:** Data integrity and verification safety: normal test execution can pollute the configured development database.
- **Recommended fix direction:** Require an explicit disposable test database for both fixture and application engines. Keep true independent-session concurrency tests; add reliable cleanup/disposal, including failures, and correct documentation. Do not replace realistic concurrency with a shared savepoint mock.
- **Architecture change:** No application architecture change; test environment boundary only.
- **Dependencies:** None. Prerequisite to running DB-writing verification for all payment fixes.
- **Suggested implementation order:** 00.
- **Suggested tests:** Refuse unsafe/non-test configuration; inspect isolation of app and fixture engines; failure-path cleanup; run both concurrency cases against disposable DB and verify no durable leftovers.
- **Can it safely wait?** Do not wait before running the backend suite. Production classification is high because this is a development safety prerequisite, not a public runtime endpoint.

#### B13 — Display checkout dismissal separately from backend PENDING

- **Issue and why it matters:** Both payment callers show Payment Cancelled after dismissal while the transaction still says PENDING.
- **Affected files/components:** `mobile/lib/providers/agent_provider.dart`; `mobile/lib/screens/payment/payment_confirmation_screen.dart`; `mobile/lib/screens/assistant/assistant_screen.dart`.
- **Security/reliability impact:** Reliability/user trust: users may believe an unresolved payment cannot settle and attempt another checkout.
- **Recommended fix direction:** Show authoritative PENDING/unknown status and separately explain that checkout was closed. Show financial CANCELLED only when returned by backend. Do not cancel by age, SDK result, or network error.
- **Architecture change:** No: presentation/state correction.
- **Dependencies:** None; coordinate B14/B15.
- **Suggested implementation order:** 12.
- **Suggested tests:** Dismissed+PENDING, dismissed+SUCCESS, dismissed+CANCELLED, status timeout; assert accurate label and no cancellation mutation or automatic second checkout.
- **Can it safely wait?** Short sandbox delay is acceptable; fix before real-user payment use.

#### B14 — Recover Assistant cards and caches after every polling outcome

- **Issue and why it matters:** Pending/null/error paths clear global busy flags but can leave a card confirming; successful Assistant payment does not refresh bill details like the manual path.
- **Affected files/components:** `mobile/lib/providers/agent_provider.dart`; `mobile/lib/models/agent_message.dart`; `mobile/lib/widgets/payment_plan_card.dart`; `mobile/lib/repositories/providers.dart`; `mobile/test/screens/assistant_screen_test.dart`.
- **Security/reliability impact:** Reliability: stuck cards, stale detail balances, and unclear recovery after a consumed confirmation.
- **Recommended fix direction:** Represent processing/unknown/recoverable UI outcomes without adding financial transaction statuses. Retain transaction reference for status recovery, stop spinners on every exit, and refresh the relevant bill detail on backend success. Recovery must not reuse a consumed token as fresh authorization.
- **Architecture change:** No: local UI lifecycle changes.
- **Dependencies:** B04 session scoping; B13; B15 for provider recovery integration.
- **Suggested implementation order:** 13.
- **Suggested tests:** Pending after all polls, null response, thrown error, delayed success, leave/reopen screen, duplicate SDK callback; assert card leaves busy state, reference retained, bills/history/details actually refresh, no extra prepare.
- **Can it safely wait?** May wait briefly in sandbox; needed before reliable user testing of interrupted payments.

#### B15 — Provide a bounded recovery path for lost callbacks

- **Issue and why it matters:** Mobile only reads local state and stops after brief polling; no mobile or scheduled caller uses the existing reconciliation endpoint.
- **Affected files/components:** `mobile/lib/repositories/payment_repository.dart`; `mobile/lib/providers/agent_provider.dart`; `mobile/lib/screens/transactions/transactions_screen.dart`; `backend/app/api/v1/endpoints/payments.py`.
- **Security/reliability impact:** Reliability: genuine provider completion can remain PENDING indefinitely in the app.
- **Recommended fix direction:** Add the smallest explicit owner-authenticated reconciliation/status recovery action for existing transactions after validation is hardened; use bounded retries/backoff. A scheduler is not required by this backlog. Preserve NOT_FOUND as unresolved, not failed or cancelled.
- **Architecture change:** No if reusing existing endpoint; a background worker would be separate architecture scope.
- **Dependencies:** B05, B10, B11; coordinate B13/B14.
- **Suggested implementation order:** 14.
- **Suggested tests:** Lost callback then validated retrieval SUCCESS; NOT_FOUND remains PENDING; expired auth; other-user request; repeat reconciliation; endpoint failure; no duplicate preparation or unlimited polling.
- **Can it safely wait?** Can wait with manual sandbox recovery; real-money launch needs an evidenced recovery procedure or this bounded entry point.

#### B16 — Collect the phone number required by existing checkout

- **Issue and why it matters:** Mobile registration omits the backend's optional phone field; initiation requires a phone and profile settings cannot supply one.
- **Affected files/components:** `mobile/lib/screens/auth/register_screen.dart`; `mobile/lib/providers/auth_provider.dart`; `mobile/lib/repositories/auth_repository.dart`; `backend/app/schemas/auth.py`; `backend/app/services/payhere.py`.
- **Security/reliability impact:** Availability: new users can prepare a payment but cannot initiate it.
- **Recommended fix direction:** Add validated phone capture using the existing registration field and define a minimal owner-authenticated completion route for existing accounts if needed. Do not fabricate phone numbers or expand into unrelated profile features.
- **Architecture change:** No for registration; a narrowly scoped profile update contract needs explicit API review.
- **Dependencies:** M6 validation/existing-user policy; B02 ownership pattern.
- **Suggested implementation order:** 15.
- **Suggested tests:** Phone round trip; absent/invalid/duplicate values; existing user completion; foreign-account update rejected; valid profile initiates; missing phone still fails safely before SDK.
- **Can it safely wait?** Can wait with seeded sandbox profiles; blocks checkout onboarding for new real users.

#### B17 — Resolve inconsistent multiple-payment-method behavior

- **Issue and why it matters:** Assistant requires exactly one method; manual UI picks methods.first and its Change button does nothing.
- **Affected files/components:** `backend/app/api/v1/endpoints/agent.py`; `backend/app/models/payment_method.py`; `mobile/lib/screens/payment/payment_confirmation_screen.dart`; `mobile/lib/repositories/payment_repository.dart`.
- **Security/reliability impact:** Reliability/consent: payment eligibility and apparent method choice differ by entry point.
- **Recommended fix direction:** Agree the existing product's selection semantics, including whether stored methods actually control SDK checkout. Make UI accurate. If selection is required, bind the owned selection into trusted plan/confirmation state while keeping confirm body confirmation_id-only. Do not silently choose the first record or invent card-vault behavior.
- **Architecture change:** Conditional: selection-in-plan may change contracts; no new payment architecture is approved.
- **Dependencies:** M6 product/API decision and M1 SDK semantics; B06/B07 if binding choice.
- **Suggested implementation order:** 16.
- **Suggested tests:** Zero/one/multiple methods; stable explicit choice; foreign method rejected; method changed/deleted after plan; confirm extras still rejected; manual and assistant display consistent selection.
- **Can it safely wait?** May wait while prototype accounts are constrained to one method; resolve before supporting multiple-method users.

#### B18 — Verify payment outcomes at their actual consumers

- **Issue and why it matters:** Current refresh tests assert dialogs, native checkout is mocked, and single-process confirmation tests do not establish restart/multi-worker behavior.
- **Affected files/components:** `mobile/test/screens/assistant_screen_test.dart:664`; `mobile/test/screens/payment_confirmation_screen_test.dart:210`; `backend/tests/test_agent_payment_confirmation.py`; `mobile/lib/services/payhere_checkout_service.dart`.
- **Security/reliability impact:** Verification reliability: passing tests can hide stale state or provider/worker incompatibility.
- **Recommended fix direction:** Add outcome assertions to existing tests; run controlled native sandbox verification separately from unit/widget tests. Include persistence-boundary tests delivered with B06/B07, not an unnecessary new test framework. Record platform/build/provider evidence without secrets.
- **Architecture change:** No: verification improvements.
- **Dependencies:** B12; relevant fixes B03–B17 before release acceptance; M1–M4.
- **Suggested implementation order:** 17 (targeted tests accompany each earlier fix).
- **Suggested tests:** Warm providers then assert new settled values; test changed bill detail; controlled callback and retrieval end-to-end on supported device; cross-worker/restart and failure tests; retain no-text-payment and ownership regressions.
- **Can it safely wait?** Automated test strengthening can be incremental; do not claim production/provider/multi-worker readiness without the corresponding evidence.


### Accepted prototype limitation

#### B19 — Request-local AI conversation sessions

- **Issue and why it matters:** Flutter retains chat but backend creates a new session for each message, so follow-up references have no server dialogue context.
- **Affected files/components:** `backend/app/agent/billing_agent.py`; `backend/app/agent/context.py`; `mobile/lib/repositories/agent_repository.dart`; `mobile/lib/providers/agent_provider.dart`.
- **Security/reliability impact:** Usability: ambiguous follow-ups fail; not permission for conversational payment execution.
- **Recommended fix direction:** For now state the limitation and request explicit bill/account details. Only add authenticated bounded conversation continuity if a later requirement justifies it; always reread bill facts and use explicit payment confirmation.
- **Architecture change:** No for clear UX; Yes/conditional for durable dialogue storage, which is not authorized here.
- **Dependencies:** B23 wording; B04 before any retained per-user context.
- **Suggested implementation order:** 18 / defer.
- **Suggested tests:** Independent requests never share another user's context; ambiguous follow-up does not execute; typed yes stays chat; future continuity would require identity/retention tests.
- **Can it safely wait?** Yes for a clearly labeled prototype. This is a proposed bounded acceptance, not a signed production risk waiver.

#### B20 — Two intentional preparation entry points

- **Issue and why it matters:** Assistant uses confirmation_id; manual payment uses authenticated prepare with explicit UI confirmation. A universal-token reading of policy conflicts with current behavior.
- **Affected files/components:** `backend/app/api/v1/endpoints/agent.py`; `backend/app/api/v1/endpoints/payments.py`; `mobile/lib/screens/payment/payment_confirmation_screen.dart`; `AGENTS.md`.
- **Security/reliability impact:** Contract reliability: a future edit could break manual checkout or incorrectly let the AI use it.
- **Recommended fix direction:** Preserve both current APIs and document the assistant-only token boundary pending owner confirmation of scope. Keep manual prepare owner-validated with backend amounts/idempotency; never expose it as an AI tool. No route unification is proposed.
- **Architecture change:** No; universal token enforcement would be a separately approved contract change.
- **Dependencies:** Manual scope decision M6; B07–B09 must cover both applicable paths.
- **Suggested implementation order:** 18 / scope decision before related contract edits.
- **Suggested tests:** Assistant cannot call prepare directly; confirmation rejects extra fields; manual requests cannot choose amount/user identity; competing entry points reuse one PENDING attempt.
- **Can it safely wait?** Yes with explicit scope documentation; do not treat this acceptance as permission to bypass the assistant gate.

#### B21 — Single-PENDING invariant currently relies on service locking

- **Issue and why it matters:** There is no partial unique database constraint, but supported prepare calls lock the bill and reuse PENDING correctly.
- **Affected files/components:** `backend/app/models/transaction.py`; `backend/app/repositories/transaction.py`; `backend/app/services/payment.py`; `backend/tests/test_payment_pending_deduplication.py`.
- **Security/reliability impact:** Defense in depth: alternate future writers could violate the invariant. Absence of a constraint alone does not prove a current duplicate-creation defect.
- **Recommended fix direction:** Keep preparation centralized and test all supported callers. Consider a partial unique constraint only after a read-only existing-data assessment and approved migration plan; do not delete historical duplicates or silently change attempts.
- **Architecture change:** No for enforcing current path; optional DB constraint is a bounded schema change requiring approval.
- **Dependencies:** B08/B09; B12 tests; M5 existing-data assessment before any constraint.
- **Suggested implementation order:** 19 / defer optional constraint.
- **Suggested tests:** Many independent prepares with different keys and manual/assistant callers yield one active transaction; terminal attempts permit new eligible attempts; future constraint tests cover existing-data compatibility.
- **Can it safely wait?** Yes while all supported writers use the lock protocol and tests pass; reassess before adding alternate writers.

#### B22 — Cancelling a plan only dismisses the local card

- **Issue and why it matters:** Local cancellation neither creates a transaction nor revokes the short-lived confirmation token on the server.
- **Affected files/components:** `mobile/lib/providers/agent_provider.dart (cancelPlan)`; `backend/app/agent/payment_confirmation.py`.
- **Security/reliability impact:** Limited consent/UX ambiguity: the token remains usable by its authenticated owner until expiry; cancellation is not a server financial operation.
- **Recommended fix direction:** Describe this as dismissing a proposal. Keep token ownership/TTL/single-use controls. Only introduce explicit revocation if required later; never equate local plan dismissal with cancellation of an existing provider transaction.
- **Architecture change:** No for wording; server revocation would add a contract and is deferred.
- **Dependencies:** B06/B07; B13 distinguishes checkout dismissal.
- **Suggested implementation order:** 19 / defer.
- **Suggested tests:** Cancel card triggers no confirm/prepare/provider request; cancelled card cannot be clicked; wrong user and expired token rejected; UI does not claim provider cancellation.
- **Can it safely wait?** Yes for prototype with short TTL and clear wording; no automatic revocation feature is required now.


### Nice-to-have improvement

#### B23 — Update stale README, prompts, and context caveats

- **Issue and why it matters:** README describes early phases/isolation; system prompt says execution is disabled despite supported button-driven preparation.
- **Affected files/components:** `README.md`; `backend/app/agent/prompts/system_prompt.py`; `backend/app/agent/payment_intent.py`; `_bmad-output/project-context.md`.
- **Security/reliability impact:** Maintainability/user clarity: stale wording encourages incorrect fixes and misleads users about the confirmation button.
- **Recommended fix direction:** Explain planning versus explicit deterministic preparation; point affirmative chat to the button without executing it. Update context evidence for both unsafe tests and refresh provenance after fixes. Correct test-safety wording with B12 rather than waiting for general polish.
- **Architecture change:** No.
- **Dependencies:** B12 for urgent safety wording; corresponding feature fixes before new claims.
- **Suggested implementation order:** 20 (safety caveat at 00).
- **Suggested tests:** Deterministic yes/confirm path creates no transaction; prompt changes do not expose execution tools; manually verify documented commands/contracts against source.
- **Can it safely wait?** General wording can wait; misleading DB-test safety text cannot wait before suite execution.

#### B24 — Protect nullable due dates and malformed-date rendering

- **Issue and why it matters:** Null handling is correct but lacks explicit tests; a malformed non-null date throws through DateTime.parse.
- **Affected files/components:** `mobile/lib/models/bill.dart`; `mobile/lib/widgets/bill_card.dart`; `mobile/lib/screens/bill_details/bill_details_screen.dart`; `mobile/test/repositories/bill_repository_test.dart`; `backend/app/schemas/bill.py`.
- **Security/reliability impact:** Reliability: malformed dates can block bill rendering; future changes may accidentally remove null support.
- **Recommended fix direction:** Add null model/repository/widget regression tests. Define the current accepted non-null date format and choose validation or safe fallback; keep DateTime? and Not available. A required nullable constructor argument is not a non-null requirement.
- **Architecture change:** No; tightening backend format may need contract review.
- **Dependencies:** M6 date-format compatibility if tightening validation.
- **Suggested implementation order:** 21.
- **Suggested tests:** due_date:null parses to null and both UIs show Not available; valid date unchanged; invalid/empty date handled per agreed policy; amounts remain exact strings.
- **Can it safely wait?** Yes while data is valid/null and current fallback works; promote if malformed production data is observed.

#### B25 — Align Assistant response guard with its comment

- **Issue and why it matters:** Confirmation handling checks only nonempty transaction ID, despite a comment claiming PENDING validation; initiation still enforces backend status.
- **Affected files/components:** `mobile/lib/providers/agent_provider.dart`; `mobile/lib/models/agent_response.dart`; `mobile/test/screens/assistant_screen_test.dart`.
- **Security/reliability impact:** UX/defense in depth: terminal replay responses lead to avoidable initiation errors, not an established backend authorization bypass.
- **Recommended fix direction:** Handle only documented statuses, query/display authoritative terminal outcomes as appropriate, and avoid unnecessary SDK launch. Keep the backend guard; do not infer success from a malformed confirmation response.
- **Architecture change:** No.
- **Dependencies:** B07 retry contract; B14 result recovery.
- **Suggested implementation order:** 22.
- **Suggested tests:** Empty ID, terminal response, unknown status, expected PENDING; assert no inappropriate initiate/SDK call and backend truth used for display.
- **Can it safely wait?** Yes because backend initiation remains the enforcement boundary.

#### B26 — Make backend dependency resolution reproducible

- **Issue and why it matters:** requirements.txt is unpinned, so rebuilding a commit may change ADK, validation, ORM, or test behavior.
- **Affected files/components:** `backend/requirements.txt`; `backend/Dockerfile`.
- **Security/reliability impact:** Reliability/supply-chain reproducibility: build behavior can drift without a source change; no specific vulnerability is asserted.
- **Recommended fix direction:** Capture the known working dependency resolution in an agreed reproducible installation policy during a separate task. Do not upgrade packages or add infrastructure merely to create this backlog.
- **Architecture change:** No application architecture change; build policy only.
- **Dependencies:** Known-working build and test evidence, B12 safe tests; manual supported-version verification before pinning.
- **Suggested implementation order:** 23.
- **Suggested tests:** Fresh builds resolve the same intended set; backend tests and representative ADK deterministic contract tests pass; no secrets in lock/build artifacts.
- **Can it safely wait?** Can wait during prototype exploration; close before a reproducible production release baseline is declared.

## Review evidence and coverage

The table maps every inconsistency in the verified context to a backlog item. The review also surfaced test isolation in a second concurrency test and a narrow provider-cardinality concern; those are included in B12 and B05. A source observation is not a guarantee of runtime/provider behavior.

| Verified context finding | Backlog item(s) |
| --- | --- |
| Public bill reads | B02 |
| Unguarded financial simulator | B01 |
| Confirmation check/consume race | B06, B07 |
| Bill freshness and amount gaps | B08, B09 |
| Initiation status race | B09 |
| Process-local tokens / multi-worker deployment | B06, B07, B18 |
| Permissive retrieval validation and first-record/cardinality concern | B05 |
| Terminal callbacks ignored | B10 |
| Provider I/O under lock | B11 |
| Mobile credential exposure | B03 |
| Cross-account cache lifetime | B04 |
| Dismissal display mismatch | B13, B14 |
| Assistant comment/implementation mismatch | B25 |
| Incomplete onboarding: phone and placeholder settings | B16 |
| Inconsistent payment-method behavior | B17 |
| Stateless chat versus conversational UI | B19 |
| Stale README/system prompt | B23 |
| Unsafe concurrency-test isolation and blanket README claim | B12, B23 |
| Assistant refresh assertion weakness; native SDK not exercised | B18 |
| Nullable due-date untested and malformed-date parsing | B24 |
| No reconciliation caller or persistent recovery after brief polling | B15 |
| No database partial unique PENDING constraint | B21 |
| Manual prepare route versus Assistant confirmation gate | B20 |
| Local-only plan cancellation | B22 |
| Unpinned backend dependencies | B26 |

### BMAD lens disposition

- **Adversarial review:** The independent review checked access boundaries, cross-component authority, provider evidence, mobile state, and operational readiness. Its verified findings map to B01–B26 above; the table preserves the distinct findings rather than dropping them for brevity. No new product capability is proposed.
- **Edge-case review:** Race and state-path findings map to B04–B11 and B13–B14: overlapping confirmation, stale bill facts, old PENDING amount, initiation versus terminal callback, worker restart, incomplete retrieval, late provider events, slow HTTP under lock, account switching, dismissal, and incomplete polling.
- **Verification-gap review:** B12 includes both committed-session concurrency tests; B18 covers weak refresh assertions, missing multi-worker confirmation coverage, and mock-only native checkout; B24 covers the untested null-date branch. The existing sequential confirmation-reuse test does not prove concurrent single-use behavior.

## Validation limits

This was static inspection and planning. No app tests, database migration, provider request, package installation, application change, commit, or push was performed. Run focused and full relevant suites only with B12's isolated disposable database, then `flutter analyze`, `flutter test`, `git diff --check`, and `git status` as required by AGENTS.md. Provider and multi-worker readiness require the manual gates and runtime evidence above.
