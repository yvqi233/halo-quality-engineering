# Failure Triage

Every failed gate remains blocking. The failure classifier assigns one deterministic kind:

- `ENVIRONMENT`: connection, health-check, or startup evidence. Recreate the disposable pinned environment before retrying.
- `PRODUCT`: an assertion disagrees with a received Halo response. Preserve API evidence and open an issue when reproducible.
- `CONTRACT`: an OpenAPI breaking-change finding. Preserve the generated difference and block the merge.
- `TEST_TOOL`: fixture serialization, cleanup, or test-code failures. Fix the test engineering defect without relabelling it as a product result.

`FLAKY_CANDIDATE` is never assigned from one failure. The stability workflow assigns it only after repeated runs with identical input contain both a pass and a failure.

`scripts/collect-evidence.ps1` writes redacted container status, Halo and PostgreSQL logs, and an HTTP health diagnostic to `artifacts/environment/`. It removes authorization credentials, cookies, the local passwords, and values for `password`, `authorization`, `cookie`, `set-cookie`, `token`, and `storageState` before an artifact is written.

Quarantines are temporary and visible. Each entry in `docs/quarantine.yaml` needs a public issue URL, owner, reason, ISO-8601 expiry, and 10-20 required green restoration runs. `scripts/validate-quarantine.mjs` rejects invalid or expired entries. Quarantined cases execute only in nightly work, remain visible in the GitHub Summary, and are excluded from the main-chain pass rate. L0 runs the validator, so an expired quarantine cannot be merged. Restore a case to the main chain after its issue is resolved and the configured consecutive green runs have completed.

## Public Evidence Boundary

Publish only redacted evidence and factual, linked results. Never copy credentials, cookies, tokens, passwords, or browser storage state into reports, screenshots, contribution records, or public issue text. A reproducible product finding should use the defect-evidence template and distinguish an open Issue, a submitted PR, and a merged PR without inferring one state from another.
