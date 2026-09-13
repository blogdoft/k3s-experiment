## Load testing the evaluation API

`.k6/evaluation-test.js` is a [k6](https://k6.io/) script that load tests Flagr's
`POST /api/v1/evaluation` endpoint directly, using the same request shape as
`FlagEvaluator` (`flagKey`, `entityContext`, `enableDebug`, `flagTags`).

With the local Flagr from `.docker/docker-compose.yml` running:

```
k6 run .k6/evaluation-test.js
```

Override target, flag key, VUs or duration via env vars:

```
k6 run -e BASE_URL=https://your-flagr-host/api -e FLAG_KEY=FeatureFlag -e VUS=50 -e DURATION=1m .k6/evaluation-test.js
```
