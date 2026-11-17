---
title: 'UI Phase 1: Billing Agent design foundation'
type: 'feature'
created: '2026-11-16'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Flutter client has a functional but minimal Material theme, duplicated presentation styling, incomplete semantic status colors, and inconsistent light/dark shared components. This prevents the existing MVP from presenting a cohesive, trustworthy fintech identity.

**Approach:** Establish the approved quiet-confidence design foundation through compatible central theme tokens and small refinements to existing shared presentation widgets. Preserve every public widget contract and all application, navigation, authentication, Assistant, payment, and PayHere behavior.

</frozen-after-approval>

## Implementation Notes

- Planned footprint: central theme and spacing/radius constants; shared button/state/bill/transaction/payment-plan presentation; one reusable status chip; focused theme/widget tests.
- Use native Flutter typography and Material theming only. Add no packages, fonts, animation, screen redesign, business logic, API/model changes, or backend changes.
- Keep existing status strings and money values unchanged; presentation may format existing string amounts but must not parse them as floating point.
- Implemented light/dark Material 3 color schemes, native typography, component themes, spacing/radius tokens, and an `AppSemanticColors` theme extension for success, pending, information, neutral, border, and subtle surfaces.
- Added presentation-only `StatusChip` and `AmountText` widgets. Adopted them in existing bill, transaction, and payment-plan cards without changing routes, callbacks, keys, status values, or money models.
- Refined `PrimaryButton` and shared empty/error views to inherit the central theme. Global progress-indicator theming provides consistent loading presentation without changing screen logic.
- Added six focused design-system tests. `flutter analyze` reports no issues; the focused tests pass 6/6 and the complete Flutter suite passes all 101 tests.
- Blind review led to explicit secondary-text roles, self-disabling loading buttons, readable disabled progress, neutral unknown statuses, responsive financial-card rows/actions, and dark/narrow regression coverage. No review finding required architecture, business-logic, or payment-flow changes.

## Review Triage Log

- `medium` — `onSurfaceVariant` was implicit, so shared secondary text could inherit primary emphasis; patched both color schemes with explicit light/dark secondary-text roles.
- `medium` — `PrimaryButton.isLoading` did not itself disable its callback; patched the shared button to enforce disabled interaction while loading.
- `medium` — the loading spinner could use low-contrast `onPrimary` over the disabled surface; patched it to use the primary semantic color and added regression coverage.
- `medium` — the payment-plan loading spinner had the same disabled-state contrast risk; patched it to select a readable color for the effective button state.
- `false` — uppercasing status text is a presentation convention only; model/API status strings remain untouched, and consistent uppercase labels are intentional for the shared chip.
- `medium` — unrecognized statuses used an informational palette that could imply meaning; patched the fallback to a neutral palette and help icon.
- `medium` — blank statuses produced an empty label; patched them to render and announce `UNKNOWN`.
- `medium` — the wider bill status chip exposed a long-biller overflow risk; patched the header with a bounded flexible title.
- `medium` — bill due-date and amount content could compete at narrow widths; patched both regions to flex with right-aligned money.
- `medium` — payment-plan header and side-by-side actions could overflow at larger text sizes; patched the header to flex and stacked the primary/secondary actions.
- `low` — transaction amounts could overconsume `ListTile` width; patched a bounded, right-aligned amount region and ellipsized the biller.
- `medium` — initial tests did not exercise adopted cards in dark/narrow layouts; added focused tests for the real shared components and loading behavior.
