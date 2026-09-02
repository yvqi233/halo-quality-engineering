# Upstream Contributions

This document has one machine-checked ledger. `pageState` records the current public GitHub page state. `lifecycleStatus` records this contribution's lifecycle independently, so a submitted PR is not described as merged merely because its page is open.

## Schema

The `upstream-ledger-v1` JSON block is parseable. Each record requires `kind`, `url`, `pageState`, `lifecycleStatus`, `haloVersion`, `sourceCommit`, and `evidence`. PR records additionally require `headCommit`. `kind` is `ISSUE` or `PR`; `pageState` is `OPEN`, `CLOSED`, `MERGED`, or `DRAFT`; `evidence` is a tracked repository path or public URL. The publication verifier resolves every record through GitHub's unauthenticated public API, checks the HTTP response, current page state, and PR head commit.

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
      "evidence": "docs/qualification-evidence.md"
    },
    {
      "kind": "PR",
      "url": "https://github.com/halo-dev/halo/pull/10283",
      "pageState": "OPEN",
      "lifecycleStatus": "SUBMITTED",
      "haloVersion": "2.26.1",
      "sourceCommit": "88c2ef14355c79a4dbd1d5c3246b3ea32836e06b",
      "headCommit": "ba1f5534ce8c5fe0e09d601ddccf0cb24a018147",
      "evidence": "docs/qualification-evidence.md"
    }
  ]
}
```
