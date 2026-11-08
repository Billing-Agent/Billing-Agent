---
title: 'Public repository maintained secret-scan gate'
type: 'chore'
created: '2026-11-08'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/public-repository-secret-exposure-audit.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Public-source readiness still requires a maintained secret scanner against the current tracked tree, every locally available ref and reachable historical/deleted content, with relevant untracked release files assessed separately.

**Approach:** Install Gitleaks outside the project if necessary, run fully local redacted scans, triage every finding as a credential, fixture, placeholder, or false positive, and record severity, affected paths/commits, rotation/history decisions, remaining manual checks, and the publication gate without exposing secret values.

</frozen-after-approval>

## Implementation Notes

### Scanner

- Gitleaks `8.30.1`, installed globally through Homebrew because it was initially unavailable. No project dependency or scanner configuration file was added.
- Gitleaks' maintained default rules were used. Both reports used `--redact=100`, remained local under `/tmp`, and were parsed without emitting candidate values.
- No `.gitleaks.toml` or `.gitleaksignore` existed in the repository, so the results used unsuppressed default rules.

Redacted command forms and outcomes:

- Current tree: `git archive HEAD | tar -x -C <temporary-tree>`, then `gitleaks dir <temporary-tree> --redact=100 --report-format=json --exit-code=42`; status `42`, the configured findings-present status.
- Full history: `gitleaks git . --log-opts="--all --full-history" --redact=100 --report-format=json --exit-code=42`; status `42`, the configured findings-present status.
- Untracked report: `gitleaks dir <report-path> --redact=100 --report-format=json --exit-code=42`; status `0`, with zero candidates.

### Scan scope

- Current tracked tree: a clean `git archive HEAD` snapshot at `d657dcbc58bfa447b869af2f0f7d18c4c08cac43`, including the tracked public `.env.example`.
- Full local history: `gitleaks git . --log-opts="--all --full-history"` across 15 locally available refs and 47 commits in a non-shallow repository. This covers every commit reachable from local branches, remote-tracking refs, tags, and Codex checkpoint refs, including removed or overwritten lines in prior file versions. Git history contains zero D-status path deletions; that count is distinct from the historical patch coverage.
- Untracked/public-release inventory: no untracked release file was present. The two debug APK paths identified by the earlier audit were absent. This report was the only untracked file created by the task; its separate Gitleaks scan returned zero candidates.
- Not covered: refs unavailable locally, hosting-service pull-request refs, release attachments, CI logs/artifacts/caches, container registries/images, backups, and previously shared files.

### Scanner results and triage

| Scope | Candidates | Classification | Redacted path / commit |
| --- | ---: | --- | --- |
| Current tracked tree | 39 | False positive: SHA-256 integrity hashes in a file manifest, not credentials | `_bmad/_config/files-manifest.csv` / current tree |
| Current tracked tree | 1 | Test fixture: synthetic password used by an authentication registration test | `backend/tests/test_security.py:169` / current tree |
| Full local history | 39 | False positive: the same SHA-256 manifest hashes | `_bmad/_config/files-manifest.csv` / `ddacdadc8a24…` |
| Full local history | 1 | Test fixture: the same synthetic test password | `backend/tests/test_security.py:169` / `11be5bec962f…` |

The history candidates are the historical occurrences of the current-tree candidates, not additional distinct secret material. No candidate was classified as a real credential, leaked placeholder/example secret, or operational key.

### Findings by severity

- Critical: 0
- High: 0
- Medium: 0
- Low: 0
- Scanner candidates triaged as non-findings: 40 per scan (39 false positives, 1 test fixture)

### Release decisions

- Rotation required by this maintained scan: **No**. The earlier audit's conditional PayHere rotation decision remains unchanged if the previously identified local APK/build artifacts were shared or their distribution cannot be ruled out.
- Git history rewrite required: **No**. No operational secret was found in the current tracked tree or locally reachable history.
- Scanned local source/history publication: **Cleared**. The tracked source and every locally available ref passed after triage.
- Overall public-repository readiness: **Conditional** until the external/manual checks below are resolved; those surfaces were not available to this local scanner.
- Temporary scan reports and the extracted tree were removed after final verification; no scanner report containing match metadata remains in the repository or task-owned `/tmp` directory.

### Remaining manual checks

- Verify remote-only and hosting-service pull-request refs, release attachments, workflow logs/artifacts/caches, container images/layers, backups, and previously shared files.
- Resolve the earlier audit's distribution question for the removed PayHere-bearing debug artifacts; rotate the affected credential if external access cannot be excluded.
- Confirm the committed development database default was never reused for a reachable or non-disposable database.

## Review Triage Log

- `low` — Scan completion evidence omitted command forms and statuses; patched with redacted commands and the two `42` findings statuses plus the report scan's `0` status.
- `low` — Default-rule results did not explicitly establish suppression state; patched by recording that no repository Gitleaks config or ignore file existed.
- `low` — Task-owned redacted reports and extracted files should not remain in `/tmp`; accepted for cleanup after the final report scan and verification.
- `low` — Zero D-status paths could be misread as the history-coverage claim; clarified that `--all --full-history` covers reachable removed/overwritten lines independently of path deletions.
