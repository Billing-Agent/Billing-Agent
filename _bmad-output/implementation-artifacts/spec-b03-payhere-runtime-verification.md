---
title: 'B03 PayHere mobile credential boundary runtime verification'
type: 'chore'
created: '2026-11-09'
status: 'complete'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: 'bc3d37394a0646ac234090dee92a263cb83fb1c0'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/b03-payhere-credential-boundary-investigation.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Static inspection shows pinned `payhere_mobilesdk_flutter` 3.1.1 does not consume the app's `merchant_secret` map key, but actual sandbox checkout, callback-signing provenance, and Retrieval API agreement remain unverified.

**Approach:** Run a controlled Android sandbox checkout from a disposable `/tmp` source snapshot whose payment map omits the key, against an isolated local database and the existing public callback configuration. Record only non-secret runtime evidence, preserve backend-authoritative settlement, then update B03 and recommend A, B, or C without changing production behavior.

## Boundaries & Constraints

**Always:** Use sandbox provider endpoints and a disposable database; keep all PayHere credentials server-side and unprinted; prove the mobile map omits `merchant_secret`; retain callback signature verification, field validation, reconciliation, ownership, and backend-only success authority; clean temporary source/database/build state afterward.

**Never:** Modify tracked application code before the runtime result; log callback bodies, provider secrets, OAuth tokens, or card data; treat Flutter completion as settlement; weaken signatures; rotate credentials; use live payments; commit or push.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| No client secret | Android sandbox app sends a payment map with no `merchant_secret` key | SDK checkout launches or returns a provider/native error that is recorded verbatim without credentials | Do not infer provider requirements from static code; classify the observed stage and stop safely |
| Genuine callback | Completed sandbox checkout posts to configured callback | Access log proves callback arrival; backend accepts only a valid signature and matching merchant/order/amount/currency | A 400 signature response is evidence of credential-boundary mismatch; transaction remains unsettled |
| Provider comparison | Checkout order is queried through server-side Retrieval credentials | Normalized provider status/order/amount/currency agree with backend evidence | Record mismatch without forcing local success |
| Client completion only | SDK invokes completion before backend settlement | Flutter polls backend and remains non-authoritative | No local success unless backend reports `SUCCESS` |

</frozen-after-approval>

## Code Map

- `mobile/lib/models/payhere_initiate.dart` -- currently inserts `merchant_secret`; do not edit tracked copy.
- `mobile/lib/services/payhere_checkout_service.dart` -- temporary `/tmp` snapshot removes the key immediately before `PayHere.startPayment` and emits only a presence boolean.
- `/Users/Nafris/.pub-cache/hosted/pub.dev/payhere_mobilesdk_flutter-3.1.1/` -- Android/iOS bridges construct native requests without a secret key; reference evidence only.
- `backend/app/api/v1/endpoints/payhere.py` and `backend/app/services/payhere.py` -- unmodified signature-first callback path.
- `backend/app/services/payment.py` and `backend/app/services/payhere_retrieval.py` -- unmodified reconciliation/provider comparison path.
- `_bmad-output/implementation-artifacts/b03-payhere-credential-boundary-investigation.md` -- update only after runtime evidence exists.

## Tasks & Acceptance

**Execution:**
- [x] Prepare a `/tmp` archive snapshot, patch only its checkout adapter to remove the key, and verify the tracked worktree remains clean.
- [x] Create/migrate isolated sandbox data, run backend and matching public tunnel, launch the Android emulator app, and stop at the user's checkout interaction.
- [x] Capture callback HTTP outcome, backend transaction state, direct Retrieval result/reconciliation behavior, and Flutter polling behavior without sensitive payloads.
- [x] Clean temporary state, update B03 with observed evidence and A/B/C recommendation, then run `git diff --check` and `git status`.

**Acceptance Criteria:**
- Given the payment map omits `merchant_secret`, when sandbox checkout is attempted, then the exact launch/error outcome is runtime-observed rather than inferred.
- Given a genuine sandbox completion, when PayHere notifies the backend, then callback verification and provider Retrieval agreement are evidenced without exposing credentials.
- Given any SDK completion callback, when Flutter renders payment state, then only backend state can produce success.
- Given cleanup completes, when Git is inspected, then only authorized BMAD evidence changes remain and no generated or secret-bearing artifact is tracked.

## Implementation Notes

- Runtime used disposable snapshot `/tmp/billing-agent-b03-runtime.sHZ2AP` at baseline commit `bc3d3739`; tracked application source was not edited.
- Temporary adapter removed `merchant_secret` immediately before `PayHere.startPayment`; Android logcat recorded key presence `false` without printing a value.
- Android 15 emulator checkout launched and completed. Backend received callback HTTP 200 before the Flutter status GET, transaction became `SUCCESS`, and the bill became `PAID` with `0.00` LKR due.
- Direct server-side Merchant Retrieval returned `SUCCESS`; order, `100.00` amount, and `LKR` currency matched, and a provider reference was present. No token, signature, credential, callback body, or provider payload is retained.
- Recommendation: A — remove mobile `merchant_secret` handling for pinned SDK 3.1.1 in a separate implementation task. Android is runtime-verified; iOS remains static-only evidence.
- On resumption after shutdown on 2026-11-16, the disposable source/database/process state and raw logs were no longer available. The contemporaneous redacted results above survived in this artifact and B03; no repeat checkout was required.

## Verification

**Commands:**
- `flutter analyze` and focused Flutter tests in the disposable snapshot -- expected: temporary adapter builds without changing tracked source.
- Redacted backend access/status and Retrieval checks -- expected: callback/reconciliation evidence with no payload or credential output.
- `git diff --check` and `git status` -- expected: no application-code changes.

**Observed:**
- Disposable snapshot `flutter analyze`: passed with no issues.
- Callback and Retrieval matrix rows: passed in the controlled Android sandbox run.
- Flutter authority row: passed; callback HTTP 200 preceded the authenticated backend status poll and only the backend `SUCCESS` produced the success UI.

**Manual checks (if no CLI):**
- In the Android emulator, log into the synthetic sandbox account, open its unpaid bill, press Confirm Payment, complete one PayHere sandbox checkout, and report only whether checkout opened/completed/errored plus the visible non-sensitive status.
