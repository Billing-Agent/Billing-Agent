---
title: 'B02: enforce ownership on both bill-read endpoints'
type: 'bugfix'
created: '2026-11-06'
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

**Problem:** Both `/api/v1/bills` detail routes read bills without JWT authentication or ownership filtering, exposing another user's billing data by UUID or biller/account number.

**Approach:** Require the existing JWT user dependency on each route and scope the service/repository lookup to that user. Return the existing bill response shape to owners and the same not-found behavior for nonexistent and foreign-owned bills. Preserve case-insensitive biller matching and avoid changes to unrelated endpoints, payment logic, AI behavior, or Flutter contracts.

</frozen-after-approval>

## Implementation Notes

- Both bill detail routes now require `get_current_user`, derive the user ID from the validated JWT, and pass it into owner-scoped service/repository lookups. The ID path uses the existing repository `get_by_user`; the biller/account query adds a `user_id` predicate while retaining `lower(biller)` matching.
- Missing and foreign-owned bills both return 404 through the existing exception handler. Successful `BillResponse` fields and the mobile `/bills/{id}` call remain unchanged. The existing unscoped service method used internally by `/me/transactions` was left untouched; no payment, AI, or Flutter files changed.
- Focused bill tests: 3 passed. Full backend suite: 217 passed, 1 dependency deprecation warning. The B12-guarded disposable database held zero application rows after testing, was dropped, and the backend container was returned to its prior stopped state.

## Review Triage Log

- **low — patched:** No test covered duplicate biller/account values across users. The focused test now verifies each JWT owner receives their own record for the shared pair.
- **low — patched:** The new owner-success assertion checked only selected fields. It now checks the complete existing response key set.
- **low — patched:** Missing-token coverage omitted malformed JWTs and a conflicting client `user_id`. Both are now tested; the token controls lookup and the client claim cannot override it.
- **false — rejected:** The unscoped `BillingService.get_bill_by_id` is a pre-existing internal method used by `/me/transactions`, whose transaction list is already owner-scoped. Neither public bill route calls it after this change; changing that separate endpoint is outside B02 and no current exposure was demonstrated.
