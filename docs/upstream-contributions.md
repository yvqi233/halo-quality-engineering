# Upstream Contributions

`pageState` records the current public GitHub page state. `lifecycleStatus` records contribution lifecycle independently: an open PR is `SUBMITTED`, and a PR is `MERGED` only when its live page reports it as merged.

## Contribution Purpose

Issue `#10282` and PR `#10283` are a single-purpose Halo quality/testability documentation improvement. The external suite identified the need to make a small, redacted, fixed-version reproducer and validation record easy to evaluate without treating an external test repository as a product defect report.

## Reproduction

The smallest credential-free curl locator is in [the Issue reproducer](../evidence/upstream-10282-reproducer.md). It fixes Halo `v2.26.1` and source commit `88c2ef14355c79a4dbd1d5c3246b3ea32836e06b`; it does not assert an authenticated Console result and it contains no private evidence.

## Expected And Actual

Expected documentation contract: state the fixed target, exact minimal action, expected interpretation, actual contribution scope, and redacted evidence location. Actual contract: the public Issue records that documentation/testability improvement, while the merged PR supplies the single-purpose upstream change and its linked validation record.

## Duplicate Search

Before opening the record, existing Halo Issues and PRs were searched for the same documentation/testability improvement. No duplicate public record was selected; `#10282` is the linked Issue for the submitted change.

## PR Change And Validation

PR `#10283` is tied to Issue `#10282`, has final head commit `0b392fb086f37cb113406e747c81939314f39ca6` and merge commit `4e7e5850b01640515323dcd4f08a1b42ff033147`, and is recorded in [the PR validation record](../evidence/upstream-10283-validation.md). The public change is single-purpose. Its public record shows maintainer approval and merge after the requested documentation revisions; SonarCloud and Codecov also reported passing results.

## AI Disclosure

Substantive AI assistance was disclosed in the public PR description. Human review remains authoritative for the submitted upstream change.

## Review And Status

Issue `#10282` current page state: `CLOSED`, lifecycle: `RESOLVED`. PR `#10283` current page state: `MERGED`, lifecycle: `MERGED`. On 2026-09-03, the public PR had five issue-comment records from `CLAassistant` (`User`), `sonarqubecloud[bot]` (`Bot`), `ruibaby` (`User`), `pkg-pr-new[bot]` (`Bot`), and `codecov[bot]` (`Bot`). It had two review records from maintainer `ruibaby` (`User`): `CHANGES_REQUESTED` on the initial head and `APPROVED` on the final head. The separate quality repository's pull request [#1](https://github.com/yvqi233/halo-quality-engineering/pull/1) later completed public [Layered quality gate run 33732942394](https://github.com/yvqi233/halo-quality-engineering/actions/runs/33732942394) successfully.

## Modification History

| Date | Record | Status |
|---|---|---|
| 2026-08-31 | Issue `#10282` created with fixed-version reproduction context | `REPORTED`, page `OPEN` |
| 2026-08-31 | PR `#10283` submitted with disclosed AI assistance and validation summary | `SUBMITTED`, page `OPEN` |
| 2026-09-02 | Public ledger verified against unauthenticated GitHub page/API responses | `SUBMITTED`, page `OPEN` |
| 2026-09-03 | Maintainer requested wording changes, revisions were applied, and the maintainer approved the final head | `APPROVED`, page `OPEN` |
| 2026-09-03 | PR `#10283` merged and linked Issue `#10282` closed as completed | PR `MERGED`; Issue `RESOLVED` |

## Schema

The `upstream-ledger-v1` JSON block is parseable. Each record requires `kind`, `url`, `pageState`, `lifecycleStatus`, `haloVersion`, `sourceCommit`, and `evidence`. PR records additionally require `headCommit`. `kind` is `ISSUE` or `PR`; `pageState` is `OPEN`, `CLOSED`, `MERGED`, or `DRAFT`. The structured contribution detail records a checked-at date, exact public comment actor/type facts, and exact review actor/type/state facts. The verifier validates that schema offline and compares it to GitHub's unauthenticated PR comment/review APIs during live verification.

<!-- upstream-contribution-detail-v1 -->
```json
{
  "schemaVersion": 1,
  "purpose": "Single-purpose Halo quality/testability documentation improvement.",
  "reproductionEvidence": "evidence/upstream-10282-reproducer.md",
  "expectedActual": "Fixed-target, redacted documentation contract and merged upstream change.",
  "duplicateSearch": "Existing public Halo Issues and PRs were searched; no duplicate was selected.",
  "prChangeHead": "PR #10283 final head 0b392fb086f37cb113406e747c81939314f39ca6; merge commit 4e7e5850b01640515323dcd4f08a1b42ff033147.",
  "validation": "Maintainer approval followed requested revisions; SonarCloud and Codecov reported passing results; the PR merged.",
  "aiDisclosure": "Substantive AI assistance was disclosed in the PR description.",
  "publicReviewFacts": {
    "checkedAt": "2026-09-03",
    "issueCommentCount": 5,
    "reviewCount": 2,
    "issueComments": [
      { "actor": "CLAassistant", "actorType": "User" },
      { "actor": "sonarqubecloud[bot]", "actorType": "Bot" },
      { "actor": "ruibaby", "actorType": "User" },
      { "actor": "pkg-pr-new[bot]", "actorType": "Bot" },
      { "actor": "codecov[bot]", "actorType": "Bot" }
    ],
    "reviews": [
      { "actor": "ruibaby", "actorType": "User", "state": "CHANGES_REQUESTED" },
      { "actor": "ruibaby", "actorType": "User", "state": "APPROVED" }
    ]
  },
  "modificationHistory": ["2026-08-31 Issue reported", "2026-08-31 PR submitted", "2026-09-02 public state verified", "2026-09-03 maintainer requested changes then approved final head", "2026-09-03 PR merged and Issue resolved"]
}
```

<!-- upstream-ledger-v1 -->
```json
{
  "schemaVersion": 1,
  "records": [
    {
      "kind": "ISSUE",
      "url": "https://github.com/halo-dev/halo/issues/10282",
      "pageState": "CLOSED",
      "lifecycleStatus": "RESOLVED",
      "haloVersion": "2.26.1",
      "sourceCommit": "88c2ef14355c79a4dbd1d5c3246b3ea32836e06b",
      "evidence": "evidence/upstream-10282-reproducer.md"
    },
    {
      "kind": "PR",
      "url": "https://github.com/halo-dev/halo/pull/10283",
      "pageState": "MERGED",
      "lifecycleStatus": "MERGED",
      "haloVersion": "2.26.1",
      "sourceCommit": "88c2ef14355c79a4dbd1d5c3246b3ea32836e06b",
      "headCommit": "0b392fb086f37cb113406e747c81939314f39ca6",
      "evidence": "evidence/upstream-10283-validation.md"
    }
  ]
}
```
