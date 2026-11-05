---
title: 'B12: isolate database-writing concurrency tests'
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

**Problem:** Two backend concurrency tests commit through independent application sessions, outside the rollback fixture, and can leave users, bills, payment methods, and transactions in the normal development database. The README incorrectly describes all backend tests as rollback-isolated.

**Approach:** Require an explicit, clearly named disposable PostgreSQL test database before importing application sessions; bind both fixture and application engines to it. Keep the independent-session requests, clean committed test rows in failure-safe teardown, dispose engines, and document the safe invocation and schema prerequisite. Do not alter production payment behavior, run migrations implicitly, or commit/push.

</frozen-after-approval>

## Implementation Notes

- Both fixture and application sessions now use the same engine, selected from an explicit `BILLING_TEST_DATABASE_URL` before application imports. A PostgreSQL/asyncpg URL with a `billing_agent_test` name is required, and the connected database name is checked.
- The two concurrency tests retain independent committed sessions. A per-test fixture deletes their transactions, payment methods, bills, and user in dependency order in `finally`; fixture rollback, app override removal, and engine disposal also use `finally`.
- README now distinguishes rollback-isolated tests from the two committed-session tests and documents the disposable database prerequisite.
- Focused concurrency tests: 2 passed. Full backend suite: 214 passed, 1 dependency warning. The missing and unsafe test-URL checks refused collection. An intentionally failing temporary probe verified cleanup of a committed row; it was removed. All four application tables held zero rows after focused, full, and failure-path runs. The disposable database was dropped and the backend container returned to its prior stopped state.
- Independent BMAD blind review found no blocking defect. Its failure-path verification suggestion was exercised with the temporary probe.
