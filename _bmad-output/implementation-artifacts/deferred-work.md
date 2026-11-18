- source_spec: `_bmad-output/implementation-artifacts/spec-ui-phase-3-recruiter-visible-screens.md`
  summary: Make pull-to-refresh indicators await completion of refreshed bill and transaction provider futures.
  evidence: Existing callbacks invalidate providers and return immediately, so the indicator can finish before the reload; changing refresh lifecycle behavior is outside this presentation-only phase.
- source_spec: `_bmad-output/implementation-artifacts/spec-ui-phase-3-recruiter-visible-screens.md`
  summary: Normalize Login and Register unexpected exceptions to a generic user-safe message while preserving known AppError text.
  evidence: Both existing auth screens display arbitrary exception strings; changing authentication error behavior was explicitly outside the requested light visual cleanup.
