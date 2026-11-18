---
title: 'UI Phase 3: Recruiter-visible screen polish'
type: 'feature'
created: '2026-11-18'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-ui-phase-1-billing-agent-design-foundation.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-ui-phase-2-payment-experience.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The remaining recruiter-visible Flutter screens still have prototype-level hierarchy, hard-coded light styling, inconsistent account masking and transaction status treatment, and controls that appear interactive despite having no implemented destination.

**Approach:** Polish Dashboard, bills, bill details, transaction history, bottom navigation, and light auth/settings presentation using only the existing Phase 1 tokens and Phase 2 visual language. Preserve every provider, route, model, validation rule, payment eligibility condition, refresh behavior, and security boundary.

</frozen-after-approval>

## Implementation Notes

- Planned footprint: existing Home, Bills, Bill Details, Transactions, Login, Register, Settings and navigation presentation; `BillCard`/`TransactionCard`; focused widget tests only.
- Preserve the four GoRouter destinations, indexed-stack branch behavior, bill/provider invalidation, exact `UNPAID` payment CTA gate, nullable due-date fallback, string money, auth controllers/validators/calls, and logout behavior.
- Reuse `AppSemanticColors`, `StatusChip`, `AmountText`, `PrimaryButton`, shared state views and spacing/radius tokens. Add no dependency, route, model, API call, fake data, analytics, chart, animation, backend change or new functionality.
- Treat current uncommitted Phase 2 files as the approved visual baseline; do not overwrite or revert them. Avoid touching Phase 2 authority wording except if a shared presentation consistency fix is strictly necessary.
- Make placeholder settings visibly disabled or informational, remove the dead notification action, and keep functional quick actions/navigation intact.
- UI/UX Pro Max guidance applied: maintain native safe areas, minimum mobile touch targets, selected/unselected navigation clarity, semantic theme colors, dynamic-text wrapping and no fixed controls obscuring scroll content. The Flutter stack search had no specific safe-area result, so native `SafeArea`/Material behavior remains the verified implementation basis.
- Dashboard now gives the Assistant primary visual weight, uses a stable “Welcome back” greeting, offers consistent functional quick actions and an explicit View all route, and removes the dead notification icon.
- Bills and details now use privacy-safe account masking (including short identifiers), shared status/money presentation, responsive metadata, nullable-date fallback and a safe-area payment CTA gated by the unchanged exact `UNPAID` condition.
- Transactions now separate status/date/amount/reference, explain PENDING as provider/backend confirmation, and replace unexpected exception strings with a user-safe fallback while retaining existing `AppError.message` values.
- Bottom navigation retains all four indexed-stack destinations and branch behavior, with a semantic top border and native safe-area treatment. Login/Register retain all keys, controllers, validation and auth calls while adopting the shared field/button hierarchy.
- Settings now presents account context, makes every placeholder visibly disabled with “Coming soon,” keeps app version informational, and preserves Logout as the sole functional action.
- Added focused Phase 3 widget coverage for short-account masking, narrow/enlarged financial cards, pending/reference presentation, bill-detail payment gating, nullable due dates, safe transaction errors, disabled settings and functional logout. Updated existing Home/Assistant expectations for intentional copy changes.
- Verification completed on 2026-11-18: `flutter analyze` reported no issues; all 39 focused tests passed; the full Flutter suite passed all 116 tests.

## Review Triage Log

- **Patched — transaction-list authority wording (medium):** Replaced the blanket “Provider-confirmed” description with lifecycle-neutral copy because the list also contains PENDING, FAILED and CANCELLED records.
- **Patched — pending transaction wording (medium):** Replaced PayHere-specific waiting copy with “awaiting final status confirmation,” which remains accurate before and after provider initiation.
- **Patched — dashboard bill ordering claim (low):** Replaced “next unpaid items” with “unpaid bills requiring attention” because the provider does not guarantee due-date sorting.
- **Deferred — refresh completion lifecycle (medium):** Existing refresh callbacks invalidate providers without awaiting the subsequent reload. This is recorded in `deferred-work.md` because changing refresh behavior exceeds this presentation-only phase.
- **Deferred — Login unexpected error disclosure (medium):** Existing unknown exceptions remain visible. This is grouped with the Register finding in `deferred-work.md` because auth error behavior was explicitly preserved.
- **Deferred — Register unexpected error disclosure (medium):** Same root cause and disposition as Login; known `AppError` behavior and auth flow remain unchanged.
- **Patched — normalized pending comparison (low):** Transaction-card pending presentation now trims status consistently with `StatusChip`.
- **Patched — narrow Settings layout (medium):** Moved the “Coming soon” badge into the subtitle column so long labels and enlarged text can wrap without trailing overflow.
- **Patched — narrow-card test constraint (medium):** The responsive card test now constrains the rendered width rather than changing only `MediaQuery` metadata.
- **Patched — disabled Settings coverage (low):** Tests now verify Notifications and Security as well as Profile and Payment Methods.
- **Patched — bill CTA routing coverage (medium):** The focused test now verifies the unchanged `/payment-confirmation` destination and the original `Bill` payload.
- **Rejected — additional indexed-stack persistence test (low):** Phase 3 did not alter `_goBranch`, route definitions or shell topology; existing navigation coverage verifies all four destinations. Adding deeper routing-behavior coverage is outside a presentation-only correction.
