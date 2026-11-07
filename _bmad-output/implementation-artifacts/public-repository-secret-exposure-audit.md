---
date: 2026-11-07
workflow: bmad-testarch-nfr
scope: public-repository secret exposure; security evidence only
status: CONCERNS
audited_commit: 8d2187b75e2a725354a4cfffcd839008b3e9aefe
branch: Dev
---

# Public-repository secret-exposure audit

**Publication decision: conditional source/history clearance; do not publish the existing APKs or the complete working directory.** No confirmed non-test secret was found in the current tracked tree or locally available Git history. However, an exact plaintext match to the local backend `PAYHERE_SECRET` was found inside two ignored debug APK copies and five ignored generated build files. This is a **High** artifact exposure finding. Whether those artifacts have already been distributed is unknown. Check existing releases, CI artifacts, and sharing history before making the repository public.

This report contains no credential values, partial values, or credential fingerprints. Hashes below identify Git commits or existing generated-file paths, never secret values. No application code, configuration, existing artifact, Git history, or credential was changed. No installation, application test, migration, provider request, rotation, commit, push, or Git fetch was performed. Only this audit artifact was added to the repository; temporary local scanning helpers retained redacted metadata only.

## Scope, method, and evidence limits

The audit followed `AGENTS.md`, `_bmad-output/project-context.md`, `_bmad-output/planning-artifacts/technical-security-backlog.md`, and the B03 investigation. BMAD's NFR evidence-audit method was scoped to the user's secret-exposure requirements: evidence, explicit uncertainty, severity, and publication gates. Performance, broader application security, reliability, and production certification were outside scope. An independent security review checked the findings and severity calibration.

The declared threshold is no non-test credential material in material being made public. Obvious examples and synthetic test values are assessed by their actual use rather than counted automatically as leaked production credentials.

| Evidence set | Coverage |
| --- | --- |
| Current tracked files | All **301** files, including configurations, README/examples, tests, generated source files, and all **6** tracked BMAD artifacts. The index and working tree were clean at the audited commit. |
| Git history | All **45** commits reachable from local branches, remote-tracking refs, and tags; **416** unique commit-reachable blobs across **301** historical paths. The repository is not shallow. Full snapshots were enumerated, so prior versions do not depend on rename detection. The explicit deletion/rename history check returned no deleted/renamed paths. |
| Additional object coverage | All **852** blobs in the local object store, including supplemental/unmapped objects, plus all **45** commit objects. Local Codex refs were inventoried. No Git LFS pointer was found; no submodule entry was found among tracked paths. |
| Local environment comparison | Root `.env` and `mobile/.env` were read only inside a local process to compare configured values with Git blobs. Values were never emitted or saved in scan results. The configured PayHere, Gemini, and JWT credential values did not match Git blobs. The local database URL matched the documented development default. |
| Existing APKs | Both local debug APK copies were inspected; they are byte-identical. One archive's **771** entries, approximately **213 MB** uncompressed, were checked for the known configured secret values, private-key headers, and environment-file entries. |
| Other generated files | **805** files under local Flutter build/cache/generated-config and local IDE paths were examined for the known PayHere secret, totaling approximately **934 MB** of candidate file data. Five matches were found. This was a known-value check, not general reverse engineering or proof that every binary contains no other secrets. |
| Ignore coverage | Non-mutating `git check-ignore --no-index` probes tested hypothetical secret, signing, build, and log paths. Global excludes were disabled for the probes so repository protections could be evaluated. No probe files were created. |

No Gitleaks, TruffleHog, detect-secrets, or Semgrep executable was available on PATH; the corresponding checked Python scanner modules were also absent. No scanner was installed. The fallback was a local Python scan combining provider/token/private-key/certificate/credential-URL patterns, project-specific credential assignment checks, entropy checks including `_` and `-`, Base64 credential-context checks, Python AST inspection of settings defaults, and manual review of redacted high-risk code/configuration. All **15** synthetic detector checks passed. This is useful coverage but is **not equivalent to a maintained scanner's full ruleset**.

Known-value comparison also covered plaintext, UTF-16LE, and Base64 forms inside the APK. The High finding was independently confirmed as an exact **plaintext** match. Provider validity, effective running-container configuration, APK provenance, and distribution history were not verified. No credential was tested against a provider. Remote-only refs, pull-request refs, release assets, CI logs, external registries, backups, and previously shared files were unavailable to this local audit.

## Findings by severity

**Critical: 0 · High: 1 · Medium: 3 · Low: 1.** These are five distinct exposure/control findings, not counts of duplicate literals. Only F01 is confirmed non-test-looking secret material in a distributable artifact; it is outside Git. No confirmed real-secret leak was found in the scanned Git source/history.

| ID | Severity | Credential type / exposure | Affected path and reference |
| --- | --- | --- | --- |
| F01 | High | Backend PayHere Merchant Secret / callback-verification credential material embedded in local build artifacts | `mobile/build/app/outputs/apk/debug/app-debug.apk`; `mobile/build/app/outputs/flutter-apk/app-debug.apk`; entry `assets/flutter_assets/kernel_blob.bin`; local ignored files, **no Git commit** |
| F02 | Medium | Executable development database password/default connection credentials | `docker-compose.yml:13`, `docker-compose.yml:42`; documented in `README.md:49` and subsequent database-test examples; current `8d2187b75e2a725354a4cfffcd839008b3e9aefe`, introduced in `34d7b7d6c97e49e3ee839e1c2882e92edcf84b26` |
| F03 | Medium | Missing exclusion coverage for credential inputs, private keys, signing containers, and local credential files | `.gitignore`, `mobile/ios/.gitignore`, `mobile/android/.gitignore`; current `8d2187b75e2a725354a4cfffcd839008b3e9aefe` |
| F04 | Medium | Environment-specific secret files can enter backend Docker build context/image | `backend/.dockerignore:1`, `backend/Dockerfile:14`; exclusion gap present since `34d7b7d6c97e49e3ee839e1c2882e92edcf84b26`, still present at audited HEAD |
| F05 | Low | Exported/copied app binaries and backend/local logs lack general ignore coverage | `.gitignore`, `mobile/.gitignore`; current `8d2187b75e2a725354a4cfffcd839008b3e9aefe`; failed probes include `release/app.apk`, `release/app.aab`, `release/app.ipa`, `backend/debug.log` |

### F01 — credential embedded in ignored builds

The APK's Dart kernel contains a value exactly equal to the root local `.env` variable `PAYHERE_SECRET`. It does not look like an obvious placeholder. Backend source uses this setting to verify PayHere callback signatures. This establishes exposure of the configured credential material in these artifacts; it does not establish the credential's provider validity, live/sandbox scope, the active server's configuration, or who has obtained the artifacts.

The same exact credential was found in these additional ignored local files:

- `mobile/.dart_tool/flutter_build/14565235c818b2a836260e40a662a41c/program.dill`
- `mobile/.dart_tool/flutter_build/14565235c818b2a836260e40a662a41c/app.dill`
- `mobile/build/471cc200544db4e61eab1c80b3eb6745.cache.dill.track.dill`
- `mobile/build/app/intermediates/assets/debug/flutter_assets/kernel_blob.bin`
- `mobile/build/app/intermediates/flutter/debug/flutter_assets/kernel_blob.bin`

All seven affected paths are ignored and absent from the scanned Git history. Do not upload, attach, or redistribute these artifacts. Ordinary Git publication of the tracked source does not include them, but a release attachment, CI artifact, workspace archive, or shared APK can.

This adds concrete build evidence to B03: an existing local build contains the same value configured for backend callback verification. It does **not** prove the build was produced from current HEAD or resolve PayHere's portal credential-selection rules. The current tracked `payhere_config.dart` still has an empty default, and no hardcoded credential was found there. A fresh build's credential boundary requires separate validation; no build was run here.

**Rotation decision:** rotate the affected PayHere credential through an authorized provider process if any affected artifact was shared, uploaded, accessible outside the trusted development environment, or its distribution history cannot be confidently established. If it remained strictly local and undistributed, third-party compromise is unconfirmed. Do not infer that unrelated Gemini/JWT/OAuth keys require rotation from this finding. No rotation occurred during this audit.

### F02 — development default is not a leaked production key

The Compose database password and README connection examples use an obvious common development default. Compose actually configures that password; it is not merely explanatory prose. The local root environment's database URL matches this default. The database port is published without an explicit loopback binding, so actual host/network exposure needs checking.

Classify this as a development configuration risk, not evidence of a leaked production credential. Before publication, confirm it has never been reused for a reachable or non-disposable database. Change it in any such environment and restrict access in a separately authorized task. A disposable local example need not be removed from history merely because its password is public. `backend/alembic.ini:89` is a generic template URL, also classified as an example rather than a discovered production secret.

### F03 — secret and signing inputs are not comprehensively ignored

Root `.env` and `.env.*` rules work at nested paths. Android `key.properties`, `.jks`, and `.keystore` protections work inside `mobile/android/`. They do not provide repository-wide signing-file protection. The detailed probe matrix below identifies the gaps. A missing rule is a future-commit risk, **not evidence that a corresponding file currently exists or was committed**.

Define dedicated local-secret/signing locations and explicit patterns in a later change; keep intentional public fixtures/examples separately reviewed. Public certificates and Firebase client configuration are not automatically private credentials. Review their contents and provider restrictions rather than treating every `.crt` or client configuration file as a leaked private key.

### F04 — Git ignore does not protect Docker images

`backend/.dockerignore` excludes `.env` but does not exclude `.env.*`, credential JSON, or private/signing files. `backend/Dockerfile` uses `COPY . .` from the backend context. Thus an environment-specific file placed under `backend/` can enter an image even though Git ignores it. The root `.env` is outside that context; this is not a claim that the current root file was copied. No existing backend image or registry was examined, and no current image leak is asserted. Align Docker context exclusions with secret storage in a separate task, then inspect any published image layers/caches.

### F05 — copied artifacts and logs

Normal Flutter `build/`, `.dart_tool/`, Android build directories, and generated platform configuration are covered. A copied APK/AAB/IPA outside these locations is not. Root/backend log paths also lack the mobile directory's `*.log` protection. F01 demonstrates why copied app artifacts require review. Add appropriate repository-wide local artifact/log patterns in a later change, and verify that no release attachment bypasses Git protections.

## Ignore-rule verification

| Family | Result from representative probes |
| --- | --- |
| `.env`, nested `.env`, `.env.test`, `.env.production`, `.env.local` | **Protected** by root `.env` / `.env.*`. Local `.env`, `.env.example`, and `mobile/.env` are untracked and ignored. The examined secret fields in `.env.example` were empty or obvious placeholders, with no match to known configured secrets; the file remains ignored and was not added. |
| Other environment/credential input names | **Missing** for `local.env`, `backend/.envrc`, `secrets.json`, `credentials.json`, `service-account.json`, `mobile/dart-defines.json`, `mobile/dart_defines.json`, and `mobile/config/dev.json`. Agree on secret-specific paths rather than ignoring all ordinary JSON/YAML configuration. |
| Android signing | **Protected within `mobile/android/`** for `key.properties`, `*.jks`, `*.keystore`. **Missing outside that subtree**, such as `signing/upload.jks`. |
| iOS signing containers/profiles | **Missing** for `.p12`, `.pfx`, and `.mobileprovision` examples under `mobile/ios/`. |
| Private keys and certificates | **Missing** for repository-level `.pem`, `.key`, `.crt`, `.cer` examples. Private keys/containers are sensitive; public-only certificates require classification, not automatic rotation. |
| Local cloud/package credentials | **Missing** for `.aws/credentials`, `.npmrc`, `.pypirc`, and generic service-account/credential JSON files. No such tracked secret file was found. |
| Firebase client configuration | `google-services.json` and `GoogleService-Info.plist` are **not ignored**. No tracked instance was found. These files are not automatically server-secret credentials; review contents/restrictions if introduced. |
| IDE files | `.idea/` and `.vscode/` are **protected**. |
| Flutter/platform generated data | Standard `mobile/build/`, `.dart_tool/`, `.gradle/`, Pods, ephemeral directories, `local.properties`, `Generated.xcconfig`, and `flutter_export_environment.sh` probes are **protected**. |
| Copied binaries and backend logs | `release/app.apk`, `release/app.aab`, `release/app.ipa`, and `backend/debug.log` are **not protected**. |

Ignore rules never remove an already tracked file and do not apply to release attachments, registry images, or arbitrary archives.

## Current-tree and history assessment

**Current tracked tree: appears free of non-test secrets within the audit's coverage; conditional source-only publication readiness.** Settings defaults for database, JWT, Gemini, and PayHere credential fields are empty/None. The backend initiation schema does not expose raw signing/OAuth secrets. The native payment adapter can receive a compile-time secret, which is a binary-distribution concern documented in B03 and confirmed for the existing builds by F01. No tracked environment file, private-key block, certificate block, real-looking provider key, or literal JWT was detected.

**Local Git history: appears free of non-test secrets within the audit's coverage; no history rewriting is indicated.** The same checks covered every historical snapshot and all object-store blobs, including prior settings and mobile configuration versions. There are no historical environment/signing/archive/log paths in the enumerated commit trees. The only credential-bearing URLs identified in tracked history were local/development or generic template URLs. Commit metadata was also scanned. No fetched remote-only or hosting-service data is included in this statement.

Test strings in `backend/tests/` and `mobile/test/` were checked in their fixture/use context. PayHere dummy secrets, mocked bearer tokens, test-user passwords, generated signatures, storage key names, and example payment references were distinguished from operational credentials. High-entropy candidates resolved to test inputs or non-credential code/example strings; none was established as a real borrowed provider credential. Synthetic tests were not treated as production exposure simply because they use a credential-shaped field.

Manual high-risk review included backend settings, database/session setup, Compose, Dockerfile/context exclusions, Alembic configuration, authentication and PayHere service/endpoint/schema/logging paths; Flutter PayHere configuration/model/service, auth/token transport, pubspec/assets, Gradle, Xcode/xcconfig files; README/examples, seed data, and BMAD artifacts. The current pubspec has no dotenv dependency or `.env` asset entry. Reviewed generated xcconfig/export files had no decoded credential-related Dart defines. Those negative checks do not override the positive APK/kernel finding.

Tracked generated plugin registration source and platform scaffold files were scanned like other source. Tracked binary files were app icons/launch images; their bytes were scanned, but no steganographic/image-content analysis was performed. No tracked app archive or private signing container was found.

## Remaining release checks and decisions

1. **Owner/developer — before making the repository public:** establish whether either affected APK or equivalent build/cache was shared through chat, download links, GitHub releases, CI artifacts, registries, backups, or collaborators. Do not paste credentials into the record. If exposure cannot be ruled out, authorize and complete PayHere rotation before external use; record only credential role, scope, and revocation completion.
2. **Merchant owner — before further binary distribution:** confirm the affected credential's sandbox/live scope and validity, current server use, and B03 mobile/backend signing relationship in the merchant portal. Confirm a future supported integration keeps any backend-accepted signing credential out of distributable app material. This audit does not alter callback or reconciliation semantics.
3. **Repository maintainer — before final source-publication clearance:** run a maintained secret scanner with full redaction against the current tracked snapshot and all refs in a complete repository copy, including remote-only/PR refs where accessible. Keep verification offline unless explicitly authorized. Triage rather than blindly suppress project-specific and test hits. Do not publish raw scanner reports.
4. **Repository/CI owner — before visibility change:** review existing release attachments, workflow logs/artifacts/caches, container images/layers, LFS storage if used elsewhere, and host-side secret-scanning alerts. These may become public independently of the clean tracked tree. No relevant tracked CI workflow was found, but server-side automation was not inspected.
5. **Developer/operations — before external access:** confirm the committed database default is restricted to disposable/local development and has not been reused. Replace it wherever non-disposable or reachable, and verify actual host binding/firewall behavior. No database access or password change was performed here.
6. **Maintainer — before accepting future release/configuration files:** close F03–F05 ignore/context gaps through an authorized change, review the exact staged files, and repeat redacted scanning after changes. Re-scan any fresh APK/IPA/AAB and confirm it does not contain backend credential material. Do not distribute the known affected builds.

**Credential rotation:** conditionally required for the PayHere credential under F01's distribution rule; conditionally required for any non-disposable database using F02's default. No evidence from this audit mandates rotation of all other keys. **Git history rewriting:** not currently indicated because no operational secret or affected APK was found in Git. If remote/history/LFS checks later find actual credential material, revoke/rotate first and plan removal separately; rewriting alone does not revoke access. Nothing was rotated or rewritten here.

## Audit gate and final workspace state

```yaml
audit_date: 2026-11-07
overall_status: CONCERNS
audited_domains:
  security: CONCERNS
  performance: N/A
  reliability: N/A
  maintainability: N/A
source_publication: CONDITIONAL
local_history_publication: CONDITIONAL
existing_debug_artifact_distribution: BLOCKED
findings:
  critical: 0
  high: 1
  medium: 3
  low: 1
confirmed_operational_secret_in_scanned_git: false
configured_secret_in_ignored_local_artifacts: true
provider_validity_verified: false
history_rewrite_indicated: false
rotation: CONDITIONAL_ON_DISTRIBUTION_OR_NONDISPOSABLE_DEFAULT_USE
```

Starting Git state: clean `Dev...origin/Dev` at `8d2187b75e2a725354a4cfffcd839008b3e9aefe`. Final repository change: this new untracked audit artifact only. Application tests were not run because no application behavior changed; the audit's scans, synthetic detector checks, and ignore probes were executed. `git diff --check` passed, and the new file was separately checked for whitespace and known configured secret values. No known secret value was present in the report. Existing B03/context/backlog artifacts were preserved.
