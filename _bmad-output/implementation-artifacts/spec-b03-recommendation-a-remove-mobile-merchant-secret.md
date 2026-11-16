---
title: 'B03 Recommendation A: remove mobile PayHere merchant secret handling'
type: 'chore'
created: '2026-11-16'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - 'AGENTS.md'
  - '_bmad-output/project-context.md'
  - '_bmad-output/implementation-artifacts/b03-payhere-credential-boundary-investigation.md'
  - '_bmad-output/implementation-artifacts/spec-b03-payhere-runtime-verification.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Flutter application still accepts `PAYHERE_MERCHANT_SECRET`, passes it through the checkout model/service, and inserts `merchant_secret` into the native payment map even though pinned `payhere_mobilesdk_flutter` 3.1.1 does not consume the key and Android sandbox runtime verification succeeded without it.

**Approach:** Remove the mobile credential configuration and plumbing, assert that the pinned SDK payment map contains no `merchant_secret`, and correct directly related setup wording. Preserve the backend `PAYHERE_SECRET`, callback verification, Retrieval credentials and flow, backend-authoritative status polling, the backend initiation contract, and its generated checkout `hash`; make no broader iOS or provider-support claim beyond static 3.1.1 evidence.

</frozen-after-approval>

## Implementation Notes

- Deleted the mobile-only `PayHereConfig` and removed the `merchantSecret` parameter plus `merchant_secret` native-map entry from `PayHereInitiateResponse` and `PayHereCheckoutService`. Both manual and Assistant checkout callers keep their existing flow and pass no new values.
- Preserved the backend initiation response model fields, including the server-generated `hash`, while continuing to omit `hash`, return URL, and cancel URL from the pinned native SDK payment map. No backend source, callback signature verification, Retrieval credentials/flow, or financial status behavior changed.
- Updated the model tests and all checkout-service test doubles. Added a real `DefaultPayHereCheckoutService` method-channel test proving the exact SDK-bound map contains neither `merchant_secret` nor web-checkout fields and still completes through the SDK callback contract.
- Updated README setup/security wording and the two superseded B03 statements in `_bmad-output/project-context.md`. Wording distinguishes Flutter package 3.1.1 runtime verification on Android from the underlying native Android SDK version; iOS remains static-only evidence.
- Earlier Android sandbox runtime verification occurred in a disposable snapshot and is recorded in the source B03 artifacts. This implementation worktree was verified locally with static analysis and automated Flutter tests; it did not repeat a provider checkout.
- Verification: focused B03 suite passed 5 tests; `flutter analyze` reported no issues; the full Flutter suite passed all 95 tests. Flutter-generated Linux/Windows plugin changes were restored, and `git diff --check` passed.

## Review Triage Log

- **low — patched:** README called 3.1.1 the Android SDK version. It now correctly identifies Flutter package 3.1.1 running on Android.
- **medium — patched:** Mandatory BMAD context still described deleted `PayHereConfig` plumbing as current. The two B03-specific statements now record Recommendation A and preserve the Android/iOS evidence boundary.
- **medium — patched:** The initial regression test exercised only the model map while checkout callers mocked the adapter. A method-channel test now exercises `DefaultPayHereCheckoutService` and inspects the actual SDK-bound arguments.
- **low — patched:** The implementation artifact lacked completion evidence. These notes record the exact boundary changes, earlier runtime evidence versus current worktree verification, and final results.
