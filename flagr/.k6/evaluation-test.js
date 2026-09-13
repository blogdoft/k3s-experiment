import http from "k6/http";
import { check } from "k6";
import { Rate, Trend } from "k6/metrics";

// Load test for Flagr's evaluation API (POST /api/v1/evaluation), matching
// the request/response contract used by BlogDoFT.Libs.Flagr's FlagEvaluator.
// Run against the local Flagr from ../.docker/docker-compose.yml (port 18000).
//
// Usage:
//   k6 run .k6/evaluation-test.js
//   k6 run -e BASE_URL=https://flagr.example.com/api -e FLAG_KEY=FeatureFlag .k6/evaluation-test.js
//   k6 run -e VUS=50 -e DURATION=1m .k6/evaluation-test.js

const BASE_URL = __ENV.BASE_URL || "http://localhost:18000/api";
const FLAG_KEY = __ENV.FLAG_KEY || "FeatureFlag";
const APPLICATION_NAME = __ENV.APPLICATION_NAME || "app3";

const evaluationErrors = new Rate("evaluation_errors");
const evaluationDuration = new Trend("evaluation_duration", true);

export const options = {
  scenarios: {
    evaluation_load: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: Number(__ENV.VUS) || 20 },
        { duration: __ENV.DURATION || "1m", target: Number(__ENV.VUS) || 20 },
        { duration: "10s", target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<300"],
    evaluation_errors: ["rate<0.01"],
  },
};

export default function () {
  const payload = JSON.stringify({
    flagKey: FLAG_KEY,
    entityContext: {
      applicationName: APPLICATION_NAME,
      entityId: `vu${__VU}-iter${__ITER}`,
    },
    enableDebug: false,
    flagTags: [],
  });

  const params = {
    headers: { "Content-Type": "application/json" },
  };

  const res = http.post(`${BASE_URL}/v1/evaluation`, payload, params);

  evaluationDuration.add(res.timings.duration);

  const ok = check(res, {
    "status is 200": (r) => r.status === 200,
    "has variantID": (r) => {
      try {
        return r.json("variantID") !== undefined;
      } catch {
        return false;
      }
    },
  });

  evaluationErrors.add(!ok);
}
