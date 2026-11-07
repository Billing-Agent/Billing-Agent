# B03 — PayHere mobile credential boundary investigation

**Status:** Investigation only, 2026-11-06. No application code, configuration, credentials, or database state was changed. The existing implementation is the source of truth. Payment authorization remains in the backend; only verified PayHere callback or reconciliation may settle a transaction.

## Finding and decision

The project pins `payhere_mobilesdk_flutter` **3.1.1**. Its Flutter-to-native Android and iOS bridges do **not** recognize or forward `merchant_secret`, even though the application adds that key to the payment object. The [provider's versioned 3.1.1 example](https://pub.dev/packages/payhere_mobilesdk_flutter/versions/3.1.1) likewise omits the key. The [current PayHere Flutter guide](https://support.payhere.lk/api-&-mobile-sdk/flutter-sdk), which documents **3.2.3**, does include it. Therefore, the extra client credential is unnecessary for the inspected 3.1.1 bridge, but whether removing it preserves an actual sandbox checkout must be verified before implementation. The native SDK binaries and merchant account configuration were not independently inspected.

The serious security question is **which Merchant Secret signs callbacks from a mobile checkout**. PayHere documents that a Merchant Secret is specific to a registered domain/app and that a callback `md5sig` is computed from a Merchant Secret, but does not clearly identify, for this app's SDK version and merchant setup, whether the mobile app credential and the backend's callback-verification credential are the same. No conclusion about their equality or derivation is justified without merchant-portal inspection and a controlled sandbox callback.

## Current project credential flow

| Name / value type | Where used | Observed role and exposure |
| --- | --- | --- |
| `PAYHERE_MERCHANT_SECRET` | `mobile/lib/core/constants/payhere_config.dart` → `payhere_initiate.dart` → `payhere_checkout_service.dart` → `PayHere.startPayment` map | Compile-time/mobile credential. A supplied value is extractable from a distributed app; `dart-define` and obfuscation do not create a secret boundary. The pinned 3.1.1 bridge ignores the map key. No nonempty default is in the current tracked source. |
| `PAYHERE_MERCHANT_ID` / response `merchant_id` | Backend initiation → Flutter payment map | Account identifier, not a signing secret. Sent to the client by design. |
| `PAYHERE_SECRET` | `backend/app/services/payhere.py` | Server-side Merchant Secret used for checkout `hash` and callback `md5sig` verification. Its value is not returned by the initiation schema. Whether it matches the app credential is **unverified**. |
| Initiation response `hash` | Backend `PayHereInitiateResponse` | Server-computed checkout request hash. It is returned by the API but omitted from the 3.1.1 native payment object. A hash for a specific order is not the raw secret. |
| `PAYHERE_API_APP_ID`, `PAYHERE_API_APP_SECRET` | Backend retrieval service/config | Separate OAuth credentials for the Merchant Retrieval API. They must remain server-side. [PayHere Retrieval API](https://support.payhere.lk/api-&-mobile-sdk/retrieval-api) documents this distinct App ID/App Secret pair. |

The backend initiation response contains merchant/order/amount/currency/payer/URL fields and a computed `hash`, but no raw Merchant Secret. The public PayHere callback verifies `md5sig` before updating the transaction. The Flutter SDK completion callback does not mark a transaction successful. Relevant tests assert that the raw secret is absent from initiation responses and that the mobile model includes the extra map field when supplied; they do not establish that the native SDK consumes it or that two real credentials differ.

## Official provider requirements and version gap

1. PayHere calls the credential created under a registered **App package name** an app-specific **Merchant Secret**. Its [current Flutter guide](https://support.payhere.lk/api-&-mobile-sdk/flutter-sdk) shows `merchant_secret` inside a one-time payment object. It also requires app package registration; live app packages require approval. This guide currently uses package `^3.2.3` and is not a faithful specification of the pinned 3.1.1 bridge.
2. The [published 3.1.1 package guide and one-time example](https://pub.dev/packages/payhere_mobilesdk_flutter/versions/3.1.1) describe registering an app-specific Merchant Secret but **omit** `merchant_secret` from the payment object. Inspection of the locally installed 3.1.1 package found no `merchant_secret` or `merchantSecret` reference in its Dart, Android Java, or iOS Swift bridge. Both platform bridges construct native checkout requests from other keys. This establishes only the wrapper's handling of the map, not undocumented native or portal behavior.
3. The [Checkout API](https://support.payhere.lk/api-&-mobile-sdk/checkout-api) says Merchant ID identifies the account; Merchant Secret is specific to the integrating domain/app. It documents a server-generated checkout `hash` and explicitly warns against generating that hash client-side because doing so exposes the secret.
4. The same [Checkout API callback specification](https://support.payhere.lk/api-&-mobile-sdk/checkout-api) computes `md5sig` using merchant ID, order ID, amount, currency, status code, and an MD5 of `merchant_secret`. PayHere says to verify this value before treating a notification as successful. The notification is server-to-server; browser/SDK completion is not settlement evidence.
5. The inspected provider guide registers one Flutter package name and lists different Android and iOS setup steps. It does **not** clearly state whether Android and iOS package/bundle identifiers require separate integration records or credentials, nor which registered app/domain secret signs a mobile notification. These are portal/provider questions. Local platform identifier inspection found Android/iOS identifiers, but their approval and credential mapping were not verified.

## Security assessment and answers to B03 questions

| Question | Verified answer / limit |
| --- | --- |
| Exact mobile credential and type | Current guide names an **app-specific Merchant Secret**, not an OAuth App Secret. For **3.1.1**, the published example and wrapper do not consume a `merchant_secret` payment key. Registration may still be required. |
| Expected in client? | Current 3.2.3 sample places it in the client payment map. That documents provider usage, not confidentiality. A client-distributed value must be treated as public. The pinned 3.1.1 wrapper has no demonstrated need to receive it. |
| Equivalent to backend secret? | **Unknown.** Both are called Merchant Secret, but PayHere says secrets are per registered domain/app. Their values, scope, and callback selection were not checked. They must not be assumed independent or equal. |
| Can it generate/validate callback signatures? | **If it is the secret used to sign that callback, yes:** the documented `md5sig` formula is reproducible by anyone holding it. If it is a different secret and PayHere signs with the backend-held secret, possession of only the mobile value should not satisfy backend verification. The actual selection is unverified. |
| Can possession forge success? | **Conditionally yes.** If the backend uses the client-exposed signing secret, a holder could compute a valid `md5sig` for a known pending order and post a forged success notification; the callback endpoint's merchant/order/amount checks do not restore secrecy. This is an inference from PayHere's formula and the project's callback implementation, not a demonstrated exploit against the configured merchant account. |
| Extra Flutter material? | **Yes for the inspected 3.1.1 bridge:** the application passes `merchant_secret` that the bridge does not read. The backend also returns a web checkout `hash` unused by this native payment map. Whether another client uses that response field must be checked before changing the API. |
| Secrets committed/printed/API-exposed? | Limited current-source and path-history inspection found no nonempty mobile default, tracked `.env`, raw secret in initiation schema, or obvious credential literal in the inspected PayHere code. A supplied build-time value would be embedded in a binary. This is **not** a complete repository-history, release-artifact, CI-log, or portal audit. |

The mobile Merchant Secret cannot by itself grant access to the backend Retrieval API: that uses separate OAuth App ID/App Secret credentials. Provider app/package restrictions may reduce unauthorized checkout attempts, but no inspected provider source says they make an embedded signing secret confidential or prevent offline calculation of `md5sig`.

## Safety verdict

| Context | Verdict |
| --- | --- |
| Restricted local sandbox prototype | **Conditionally usable for investigation.** No live money is at stake, and current source has no obvious hardcoded credential. Do not distribute the build or rely on callback integrity until the secret relationship is verified. Sandbox transaction records can still be forged if the same signing secret is exposed. |
| Public GitHub repository | **Not cleared yet.** The current tracked source inspection found no obvious real value, but complete current/history secret scanning, CI/config review, and any release artifact review remain outstanding. Publishing source does not make `dart-define` safe in a distributed binary. |
| Production | **Not cleared.** Resolve the provider credential/callback mapping, remove unnecessary client credential handling for the pinned version if confirmed, and prove signed callback plus retrieval behavior with a controlled checkout. If the only supported mobile integration requires exposing the very secret the backend uses to accept success callbacks, use a provider-supported backend-signed checkout integration instead. |

## Recommended B03 implementation direction — no changes made

1. **Verify first:** In the PayHere sandbox merchant portal, identify the credential record for the Android package, iOS bundle ID, and backend/checkout domain using only labels and fingerprint comparisons; never put values in a report. Ask PayHere support which record signs mobile SDK notifications for package 3.1.1. Run a controlled sandbox checkout with `PAYHERE_MERCHANT_SECRET` absent and inspect whether the pinned SDK still initiates, followed by a genuine callback and Retrieval API check. This is the gate for any code edit.
2. **If 3.1.1 works without the extra map key:** remove `PAYHERE_MERCHANT_SECRET` handling from `mobile/lib/core/constants/payhere_config.dart`, the `merchantSecret` argument and `merchant_secret` map field in `mobile/lib/models/payhere_initiate.dart`, and the pass-through argument in `mobile/lib/services/payhere_checkout_service.dart`; update related Flutter tests and setup text. Keep `PAYHERE_SECRET` and Retrieval OAuth credentials server-side. Review consumers before removing the unused response `hash`; preserve API contracts unless a separate change is justified.
3. **If a supported SDK version truly requires a client Merchant Secret:** first prove it cannot validate callbacks accepted by this backend. If PayHere cannot supply an independent backend-verifiable callback secret for mobile checkout, migrate initiation to PayHere's [backend-signed Checkout API](https://support.payhere.lk/api-&-mobile-sdk/checkout-api) or another provider-confirmed hosted checkout flow that keeps the callback key on the server. Confirm mobile UX and app/domain registration with PayHere before designing the change. Do not remove or weaken callback signature verification or reconciliation.
4. Correct code comments and README/setup wording that presently present the client secret as unquestionably required for the pinned SDK. Do this with the eventual implementation, after the manual gate.

## Manual verification gates

- Merchant portal: verify sandbox and eventual live integration records, approved package/bundle/domain identities, and whether mobile and backend secret **fingerprints** match. Record only equality/inequality and record labels, never values.
- PayHere support or provider documentation: clarify which secret signs notifications from a 3.1.1 mobile checkout, whether separate Android/iOS app registrations are needed, and whether a distinct backend callback verification key is supported.
- Controlled sandbox: checkout on both platforms with the extra mobile key omitted; observe actual SDK result, signed callback, backend state, and Retrieval API result. Use test merchant records only, and do not log credentials or full payloads.
- Inspect build/release pipeline, prior artifacts, and full Git history with a secret scanner before public release. Treat any discovered real exposure through the normal credential incident process; this investigation does not rotate or rewrite history.

## Public-repository exposure checklist

- [x] Current tracked PayHere config has no nonempty embedded credential default; no tracked `.env` path was found in the limited path scan.
- [x] Initiation response schema does not include raw `PAYHERE_SECRET` or Retrieval App Secret.
- [x] Credential-bearing source paths were identified in Git history; the prior mobile config revision checked had no nonempty default or obvious literal assignment.
- [ ] Run a full current-tree **and all-history** secret scan, including non-PayHere naming and deleted files, with results redacted.
- [ ] Review CI variables, build commands, logs, crash reports, and distributed APK/IPA artifacts for `PAYHERE_MERCHANT_SECRET` and backend credentials.
- [ ] Confirm app/endpoint credential scope and equality in the PayHere portal; resolve callback signing provenance.
- [ ] Ensure `.env`, `dart-define` input files, certificates, and generated build artifacts are excluded from publication.
- [ ] Repeat the check before publishing or changing the integration.

## Evidence inspected and limits

Repository: `AGENTS.md`, `_bmad-output/project-context.md`, `_bmad-output/planning-artifacts/technical-security-backlog.md`; `README.md`; `mobile/pubspec.yaml`/`pubspec.lock`; mobile PayHere config/model/checkout service and both checkout callers; backend settings, PayHere service, callback endpoint/schema, Retrieval service; relevant mobile/backend PayHere tests; Git status, tracked paths, and limited credential-bearing path history. Locally installed published 3.1.1 Dart/Android/iOS bridge code was inspected. No `.env` values, real credentials, merchant portal, native binary internals, runtime SDK calls, or live/sandbox checkout were accessed. No tests were run because this was a documentation and code investigation.

Primary sources: [PayHere Flutter SDK guide](https://support.payhere.lk/api-&-mobile-sdk/flutter-sdk), [published Flutter package 3.1.1](https://pub.dev/packages/payhere_mobilesdk_flutter/versions/3.1.1), [PayHere Checkout API and notification verification](https://support.payhere.lk/api-&-mobile-sdk/checkout-api), [PayHere Retrieval API](https://support.payhere.lk/api-&-mobile-sdk/retrieval-api). Provider guides were accessed on 2026-11-06. Current provider guidance and the pinned package differ; the manual gates above prevent treating the newer sample as proof of 3.1.1 runtime behavior.
