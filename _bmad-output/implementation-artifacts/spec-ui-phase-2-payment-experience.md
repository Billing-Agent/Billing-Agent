---
title: 'UI Phase 2: Assistant and payment experience polish'
type: 'feature'
created: '2026-11-18'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-ui-phase-1-billing-agent-design-foundation.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Assistant, payment-plan review, manual payment confirmation, and payment-result UI still use prototype-level hierarchy, duplicated presentation, hard-coded light colors, and ambiguous progress feedback despite the Phase 1 design foundation.

**Approach:** Polish only those portfolio-critical surfaces with the existing tokens and shared widgets, consolidate payment-result presentation, and add accurate provider/backend trust and progress copy while preserving every API, callback, confirmation, polling, navigation, and financial-status behavior.

</frozen-after-approval>

## Implementation Notes

- Planned footprint: `AssistantScreen`, `PaymentConfirmationScreen`, `PaymentPlanCard`, one shared presentation-only payment-result dialog, and focused widget-test updates.
- Preserve dialog route tracking, authenticated-session cleanup, confirmation-ID-only execution, prepare/initiate/SDK/polling order, retry idempotency reset, result keys, and existing backend-authoritative status branches.
- Use Phase 1 `AppSemanticColors`, `StatusChip`, `AmountText`, spacing/radius tokens, and native Flutter `SafeArea`; add no design system, dependency, model, provider, repository, route, API, backend, animation, or fake functionality.
- Replaced the two duplicated result-dialog layouts with `PaymentResultDialog`; each caller still owns route cleanup, retry behavior, navigation, and financial-state decisions.
- Added explicit presentation-only progress stages for opening PayHere Sandbox and confirming status with the backend. The existing `_isLoading` lock and prepare/initiate/SDK/polling sequence remain unchanged.
- Removed the non-functional payment-method Change action and unlinked Terms copy rather than presenting unavailable interactions.
- Added focused coverage for the Assistant safety boundary and prompt chips, confirmation-screen masking/sandbox/trust/progress states, and shared SUCCESS/PENDING/FAILED/CANCELLED result wording.
- Verification: `flutter analyze` reports no issues; full `flutter test` passes 111 tests.

## Review Triage Log

- `medium` — “Opening PayHere” was shown during backend preparation; patched so the stage begins only immediately before the SDK handoff.
- `medium` — active progress could be below the viewport; patched into the fixed safe-area action surface.
- `low` — progress changes lacked live-region semantics; patched with a semantic live region and stage label.
- `medium` — four-character account identifiers were displayed in full; patched so short identifiers remain fully masked and covered by a widget test.
- `low` — result amounts bypassed `AmountText`; patched to use the shared formatter and updated focused assertions.
- `medium` — FAILED copy promised retry even when the caller supplied no retry action; patched with action-aware recovery wording.
- `low` — pending confirmation copy remained on terminal plan cards; patched with state-specific header and boundary copy.
- `low` — the plan’s bill status was ambiguously labelled as payment status; patched with `Bill status` and `Plan status` labels.
- `low` — the account detail repeated its label in the value; patched to render only the masked value.
- `medium` — pre-checkout confirmation used `PROCESSING`; patched to the more accurate `CONFIRMING` semantic state.
- `low` — tapping a suggestion discarded a composed draft; patched so prompt sends preserve unrelated text and covered by a widget test.
- `medium` — unknown result states inherited pending semantics; patched to normalize them to a neutral `UNKNOWN` presentation with focused coverage.
