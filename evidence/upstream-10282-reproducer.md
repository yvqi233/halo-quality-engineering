# Issue 10282 Reproducer

Target: Halo `v2.26.1`, source commit `88c2ef14355c79a4dbd1d5c3246b3ea32836e06b`.

```bash
curl --fail-with-body --silent --show-error \
  http://127.0.0.1:8090/apis/api.console.halo.run/v1alpha1/posts \
  -H 'Accept: application/json'
```

Expected documentation contract: the public contribution describes the request surface, fixed target, and the smallest externally repeatable setup without credentials or private artifacts. Actual contribution contract: Issue `#10282` records that quality/testability documentation improvement and its minimal reproduction context. The command intentionally has no authentication material and is a reproducer locator, not a claim that an unauthenticated Console request succeeds.
