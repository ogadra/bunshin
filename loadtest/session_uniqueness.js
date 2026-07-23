import { RUNNER_COUNT, createSession, deleteShell } from "./common.js";

export const options = {
  scenarios: {
    session_uniqueness: {
      executor: "shared-iterations",
      vus: RUNNER_COUNT,
      iterations: RUNNER_COUNT,
      maxDuration: "60s",
      gracefulStop: "10s",
    },
  },
  thresholds: {
    checks: ["rate==1.0"],
    http_req_failed: ["rate==0.0"],
    http_req_duration: ["p(95)<5000"],
  },
};

export default function () {
  const cookies = createSession();
  console.log(`SESSION_ID:${cookies.sessionId}`);
  deleteShell(cookies);
}
