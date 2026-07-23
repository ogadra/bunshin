import http from "k6/http";
import { check } from "k6";
import { Counter } from "k6/metrics";
import { BASE_URL, RUNNER_COUNT, getCookie } from "./common.js";

const overflowSessionsCreated = new Counter("overflow_sessions_created");

export const options = {
  scenarios: {
    capacity_overflow: {
      executor: "shared-iterations",
      vus: RUNNER_COUNT + 10,
      iterations: RUNNER_COUNT + 10,
      maxDuration: "120s",
      gracefulStop: "10s",
    },
  },
  thresholds: {
    checks: ["rate==1.0"],
    http_req_duration: ["p(95)<10000"],
    overflow_sessions_created: [`count==${RUNNER_COUNT}`],
  },
};

export default function () {
  const res = http.post(`${BASE_URL}/api/shell`, null, {
    redirects: 0,
  });

  check(res, {
    "overflow: status is 204 (runner allocated) or 503 (no idle runner)": (r) =>
      r.status === 204 || r.status === 503,
  });

  if (res.status === 204) {
    overflowSessionsCreated.add(1);
    const sessionId = getCookie(res, "session_id");
    const shellId = getCookie(res, "shell_id");
    if (sessionId && shellId) {
      console.log(`CLEANUP:${sessionId}:${shellId}`);
    }
  }
}
