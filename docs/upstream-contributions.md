# Upstream Contributions

`pageState` records the current public GitHub page state. `lifecycleStatus` records contribution lifecycle independently: an open PR is `SUBMITTED`, and no record is described as merged or accepted unless its live page is merged.

## Contribution Purpose

Issue `#10282` and PR `#10283` are a single-purpose Halo quality/testability documentation improvement. The external suite identified the need to make a small, redacted, fixed-version reproducer and validation record easy to evaluate without treating an external test repository as a product defect report.

## Reproduction

The smallest credential-free curl locator is in [the Issue reproducer](../evidence/upstream-10282-reproducer.md). It fixes Halo `v2.26.1` and source commit `88c2ef14355c79a4dbd1d5c3246b3ea32836e06b`; it does not assert an authenticated Console result and it contains no private evidence.

## Expected And Actual

Expected documentation contract: state the fixed target, exact minimal action, expected interpretation, actual contribution scope, and redacted evidence location. Actual contract: the public Issue records that documentation/testability improvement, while the submitted PR supplies the single-purpose upstream change and its linked validation record.

## Duplicate Search

Before opening the record, existing Halo Issues and PRs were searched for the same documentation/testability improvement. No duplicate public record was selected; `#10282` is the linked Issue for the submitted change.

## PR Change And Validation

PR `#10283` is tied to Issue `#10282`, has head commit `ba1f5534ce8c5fe0e09d601ddccf0cb24a018147`, and is recorded in [the PR validation record](../evidence/upstream-10283-validation.md). The public change is single-purpose. SonarCloud passed; license and CLA checks are pending.

## AI Disclosure

Substantive AI assistance was disclosed in the public PR description. Human review remains authoritative for the submitted upstream change.

## Review And Status

Issue `#10282` current page state: `OPEN`. PR `#10283` current page state: `OPEN`, not draft; lifecycle: `SUBMITTED`. Public CI has no run URL for this quality repository. The upstream PR validation status is SonarCloud passed with license and CLA pending; no merged or accepted status is claimed.

## Modification History

| Date | Record | Status |
|---|---|---|
| 2026-08-31 | Issue `#10282` created with fixed-version reproduction context | `REPORTED`, page `OPEN` |
| 2026-08-31 | PR `#10283` submitted with disclosed AI assistance and validation summary | `SUBMITTED`, page `OPEN` |
| 2026-09-02 | Public ledger verified against unauthenticated GitHub page/API responses | `SUBMITTED`, page `OPEN` |

## Schema

The `upstream-ledger-v1` JSON block is parseable. Each record requires `kind`, `url`, `pageState`, `lifecycleStatus`, `haloVersion`, `sourceCommit`, and `evidence`. PR records additionally require `headCommit`. `kind` is `ISSUE` or `PR`; `pageState` is `OPEN`, `CLOSED`, `MERGED`, or `DRAFT`. The verifier checks every HTTP(S) URL in this document and README evidence links, then uses GitHub's unauthenticated public API additionally for the current state and PR head.

<!-- upstream-ledger-v1 -->
```json
{
  "schemaVersion": 1,
  "records": [
    {
      "kind": "ISSUE",
      "url": "https://github.com/halo-dev/halo/issues/10282",
      "pageState": "OPEN",
      "lifecycleStatus": "REPORTED",
      "haloVersion": "2.26.1",
      "sourceCommit": "88c2ef14355c79a4dbd1d5c3246b3ea32836e06b",
      "evidence": "evidence/upstream-10282-reproducer.md"
    },
    {
      "kind": "PR",
      "url": "https://github.com/halo-dev/halo/pull/10283",
      "pageState": "OPEN",
      "lifecycleStatus": "SUBMITTED",
      "haloVersion": "2.26.1",
      "sourceCommit": "88c2ef14355c79a4dbd1d5c3246b3ea32836e06b",
      "headCommit": "ba1f5534ce8c5fe0e09d601ddccf0cb24a018147",
      "evidence": "evidence/upstream-10283-validation.md"
    }
  ]
}
```
