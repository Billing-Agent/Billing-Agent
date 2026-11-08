---
title: 'F03-F05 public repository hardening'
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

**Problem:** Findings F03-F05 identify gaps that could allow local secret inputs, signing material, copied mobile packages, logs, or backend-context credentials into Git or a backend Docker image.

**Approach:** Preserve the existing ignore and safe example-file work, add only missing targeted protections without broadly excluding public JSON/YAML/certificate configuration, verify representative paths with `git check-ignore`, and remove only audit-confirmed reproducible Flutter artifacts if they still exist.

</frozen-after-approval>

## Implementation Notes

- Preserved the pre-existing `.gitignore` additions covering local environment inputs, named credential JSON files, package/cloud credentials, targeted private/signing material, copied APK/AAB/IPA packages, and local logs.
- Preserved the pre-existing `backend/.dockerignore` additions covering environment-specific files, named credential JSON files, package/cloud credentials, and targeted private/signing material in the backend Docker context.
- Preserved `.env.example` unchanged. Its sensitive fields are empty and its database URL is an obvious placeholder; the Git negation rules intentionally keep it eligible for tracking as a public template.
- No further ignore-file edit was necessary: representative positive probes resolve to the new rules, while ordinary JSON/YAML, public certificate files, Firebase client configs, and `.env.example` remain eligible for tracking.
- All seven audit-confirmed Flutter build/cache paths were already absent when inspected, so no generated file was deleted.
- Blind review prompted narrow additions for common private-key PEM basenames and credential JSON variants in both Git and Docker exclusions, plus local-log exclusion from the backend Docker context. Patterns remain filename-specific and do not broadly exclude JSON, YAML, PEM, or certificate files.
- The review's `.env.example` completeness suggestion was intentionally not applied because synchronizing non-security settings is outside F03-F05; the existing template remains unchanged and contains placeholders only.

## Review Triage Log

- `medium` — Backend-local logs were Git-ignored but could still enter the backend `COPY . .` context; patched with a targeted Docker `**/*.log` rule.
- `medium` — Filename-targeted PEM protection missed common private server/TLS/signing key basenames; patched with explicit key-oriented PEM names without ignoring all PEM or certificate files.
- `medium` — Credential JSON protection missed common service-account/application-default naming variants; patched with explicit credential-oriented basenames and prefixes without ignoring all JSON.
- `low` — `.env.example` does not mirror every current backend setting, but its sensitive values are empty or obvious placeholders; rejected for this task because full template synchronization is outside F03-F05 and the requested existing file was preserved.
