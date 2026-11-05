---
title: 'B01: disable unauthenticated payment simulator by default'
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

**Problem:** The unauthenticated development payment-simulation route is always registered and can mark a transaction SUCCESS and its bill PAID without PayHere evidence.

**Approach:** Keep the existing simulator for isolated local/test workflows, but make its route absent by default and in production-like configuration. Require explicit nonproduction enablement and a disposable test database. Verify default absence, explicit test availability, and unaffected signed PayHere callback behavior without changing production settlement logic.

</frozen-after-approval>

## Implementation Notes

- `Settings` defaults to `APP_ENVIRONMENT=production` and `ENABLE_DEV_PAYMENT_SIMULATOR=false`. Router registration additionally requires `development` or `test`, a PostgreSQL/asyncpg `billing_agent_test` database name, and a separate simulator token of at least 32 characters.
- The enabled test/development route rejects requests lacking the `X-Dev-Simulator-Token` header or carrying a wrong token with 404. A normal JWT is insufficient. The existing `PaymentService.simulate_success` and PayHere callback/reconciliation logic were not changed.
- The B12 test harness explicitly enables the route only after selecting its disposable database. Existing simulator tests send the test-only header; new tests cover default settings, absent route under production/normal-database configurations, JWT-only denial, and signed/invalid PayHere callbacks with the simulator absent.
- Focused B01 tests: 6 passed. Full backend suite: 216 passed, 1 dependency deprecation warning. The disposable database held zero application rows after testing, was dropped, and the backend container was returned to its prior stopped state.

## Review Triage Log

- **medium — patched:** The explicitly enabled route remained unauthenticated. A separate simulator token now prevents unauthenticated and ordinary JWT users from invoking it, even in the isolated test/development configuration.
- **low — patched:** README lacked safe simulator configuration instructions. It now documents the nonproduction flag, disposable database, token, and request header without publishing a credential.
- **medium — patched:** Route tests patched the global settings object but did not check actual defaults. A test now constructs `Settings` with environment sources cleared and asserts the production/disabled defaults.
- **low — patched:** Invalid callback signatures were not tested on an app without the simulator. The protected-app callback test now verifies both signed success and invalid-signature rejection.
