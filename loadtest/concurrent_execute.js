import http from "k6/http";
import { check } from "k6";
import {
  BASE_URL,
  RUNNER_COUNT,
  cookieHeader,
  createSession,
  deleteShell,
} from "./common.js";

export const options = {
  scenarios: {
    concurrent_execute: {
      executor: "shared-iterations",
      vus: RUNNER_COUNT,
      iterations: RUNNER_COUNT,
      maxDuration: "120s",
      gracefulStop: "10s",
    },
  },
  thresholds: {
    checks: ["rate==1.0"],
    http_req_failed: ["rate==0.0"],
    http_req_duration: ["p(95)<10000"],
  },
};

export default function () {
  const cookies = createSession();
  const cookie = cookieHeader(cookies);

  const lsRes = http.post(
    `${BASE_URL}/api/execute`,
    JSON.stringify({ command: "ls" }),
    {
      headers: {
        "Content-Type": "application/json",
        Cookie: cookie,
      },
      timeout: "30s",
    },
  );
  check(lsRes, {
    "POST /api/execute (ls) returns 200": (r) => r.status === 200,
    "ls response contains complete event": (r) =>
      r.body.includes('"type":"complete"') ||
      r.body.includes('"type": "complete"'),
    "ls response contains exitCode 0": (r) =>
      r.body.includes('"exitCode":0') || r.body.includes('"exitCode": 0'),
  });

  const echoRes = http.post(
    `${BASE_URL}/api/execute`,
    JSON.stringify({ command: "echo hello" }),
    {
      headers: {
        "Content-Type": "application/json",
        Cookie: cookie,
      },
      timeout: "30s",
    },
  );
  check(echoRes, {
    "POST /api/execute (echo) returns 200": (r) => r.status === 200,
    "echo response contains complete event": (r) =>
      r.body.includes('"type":"complete"') ||
      r.body.includes('"type": "complete"'),
    "echo response contains exitCode 0": (r) =>
      r.body.includes('"exitCode":0') || r.body.includes('"exitCode": 0'),
  });

  deleteShell(cookies);
}
