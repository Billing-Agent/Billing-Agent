---
title: 'B04: isolate Flutter state across account transitions'
type: 'bugfix'
created: '2026-11-09'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - 'AGENTS.md'
  - '_bmad-output/project-context.md'
  - '_bmad-output/planning-artifacts/technical-security-backlog.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Flutter keeps bills, bill details, payment methods, transactions, payment status, Assistant messages/plans/confirmation state, and local payment progress outside the authenticated identity lifecycle. Logout or an account switch can therefore expose prior-account state, while delayed requests, 401 responses, or PayHere callbacks can affect a newer session.

**Approach:** Introduce a unique authenticated-session token derived from auth transitions; make every user-scoped Riverpod provider depend on it; and reject async/provider/SDK results after their originating session is superseded. Reset local payment progress and hide its prior bill when the session changes, while preserving global infrastructure, normal same-session caching, API contracts, backend authority, and existing payment behavior.

</frozen-after-approval>

## Implementation Notes

- Added a unique `AuthenticatedSession` lifetime derived from `authProvider`. Bills, bill details, payment methods, transactions, payment status, and Assistant state now depend on that lifetime, return no user data while unauthenticated, and discard results after their originating session is invalidated.
- Logout invalidates the mobile session and clears the in-memory bearer token before secure-storage cleanup. `ApiClient` also tracks auth generations so delayed storage reads cannot replace a newer token and stale 401 responses cannot log out the newer session.
- Assistant chat/confirmation/initiation/polling and manual payment preparation/initiation/polling/SDK callbacks verify their originating session after every asynchronous boundary. Account transitions clear Assistant drafts, chat/payment-plan state, manual idempotency/transaction progress, hide the previous bill, and remove the exact open result-dialog route without relying on navigation redirects.
- Preserved global infrastructure providers (API client, repositories, services, router, checkout adapter, token storage), all backend/API contracts, and backend-authoritative payment status behavior. No backend or payment logic changed.
- Added focused provider, auth, API-client, Assistant widget, and manual-payment widget coverage for logout clearing, A-to-B isolation, late requests/confirmation/SDK callbacks, stale 401/storage races, same-account re-login, open dialog/draft clearing, and ordinary same-session caching/chat continuity.
- Verification: `flutter analyze` completed with no issues; the full Flutter suite passed all 97 tests. Generated Linux/Windows plugin-file changes produced by Flutter tooling were restored. `git diff --check` passed.

## Review Triage Log

- **medium — patched:** A delayed secure-storage read could overwrite a newer in-memory token. The storage result is now applied only when the auth generation is unchanged, with a delayed-read regression test.
- **medium — patched:** Logout previously left the authenticated session active during secure-storage deletion. State and the in-memory token are now invalidated synchronously before repository cleanup, with blocked-cleanup coverage.
- **false — rejected:** Overlapping restore/login/logout operations were proposed as a reachable stale-auth path, but current routing exposes neither logout while startup/login is loading nor login while authenticated. The reachable cross-session sources—old API requests, storage reads, 401s, Assistant work, and SDK callbacks—are generation/session guarded by this change; broader authentication-operation orchestration would be a separate redesign without a demonstrated caller.
- **medium — patched:** Session listeners used a top-route `pop`, which could dismiss an unrelated newer route. Each result dialog now records its exact `Route` and removes that route on session change.
- **medium — patched:** Cross-session Assistant payment tests initially stopped at chat responses. Coverage now includes delayed confirmation, checkout suppression, late SDK callback suppression, polling suppression, and no result callback/new-session mutation.
- **low — patched:** Initial tests omitted same-account re-login and Assistant-local draft/dialog cleanup. Focused provider and widget tests now cover both.
