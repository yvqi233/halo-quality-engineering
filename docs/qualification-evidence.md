# Qualification Evidence

This tracked record transcribes the completed local qualification evidence used by the public documentation. It is not a hosted CI report.

| Evidence | Observed value | Source location |
|---|---|---|
| Target | Halo `v2.26.1`, source commit `88c2ef14355c79a4dbd1d5c3246b3ea32836e06b`; image `halohub/halo@sha256:37d0de36041e7da32a1f2d4ea02aa18f2f0e2757949d59e2e2659fac734f5ab9` | `environment/image-lock.env` |
| Stability | 20 consecutive All-layer `PASS`/`NONE` records at `04379a211124cd52f7a2d08920dd0866fe24ed55`; `163.370s` min, `182.204s` max, `168.103s` average | `artifacts/stability/runs.jsonl` |
| Full gate | L0 `41.640s`, L1 `65.072s`, L2 `77.769s`; all `PASS`; preflight missing count `0`; final Compose rows `0` | completed Task 9 local gate evidence |
| Firefox | ordinary `I01`, `I02`, and `E01-E09`: 11/11; isolated `E10`: 1/1; user journeys `E01-E10`: 10; retries: `0` | completed Firefox local qualification evidence |

The repository has no remote and there is no public CI run URL.
