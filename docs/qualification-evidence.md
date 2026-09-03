# Qualification Evidence

This page locates the evidence. The machine-readable facts are the tracked [qualification artifact](../evidence/qualification-v1.json), which is a sanitized local qualification snapshot captured before the repository was published. It is not a hosted CI report.

| Evidence | Observed value | Source location |
|---|---|---|
| Target | Halo `v2.26.1` source commit and image digest | `evidence/upstream-10282-reproducer.md` and `artifacts/stability/runs.jsonl` |
| Stability | 20 consecutive All-layer records and durations | `artifacts/stability/runs.jsonl` and `evidence/qualification-v1.json` |
| Full gate | L0-L2 outcomes and durations, with required ordinary/expiry phase completion | `evidence/qualification-v1.json` |
| Firefox | Ordinary and isolated JUnit outcomes and journey count | `evidence/qualification-v1.json` |

After publication, pull request [#1](https://github.com/yvqi233/halo-quality-engineering/pull/1) completed public [Layered quality gate run 33732942394](https://github.com/yvqi233/halo-quality-engineering/actions/runs/33732942394). Its `L0 contract`, `L1 API smoke`, and `L2 Chromium E2E` jobs all concluded successfully. This hosted run is separate from the 20 local stability records and does not change their provenance.
