/**
 * Quick k6 Load Test for RepStack Backend
 */
import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend } from "k6/metrics";

const errorRate = new Rate("errors");
const healthLatency = new Trend("health_latency");
const authLatency = new Trend("auth_latency");

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";

export const options = {
  vus: 5,
  duration: "20s",
  thresholds: {
    http_req_duration: ["p(95)<500"],
    errors: ["rate<0.1"],
  },
};

function graphql(query, variables = {}, token = null) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  return http.post(`${BASE_URL}/graphql`, JSON.stringify({ query, variables }), { headers });
}

export default function () {
  // Health check
  group("Health Check", () => {
    const start = Date.now();
    const response = http.get(`${BASE_URL}/health`);
    healthLatency.add(Date.now() - start);

    check(response, {
      "health status is 200": (r) => r.status === 200,
      "health returns ok": (r) => JSON.parse(r.body).status === "ok",
    });
    errorRate.add(response.status !== 200);
  });

  // Authentication flow
  group("Sign Up", () => {
    const email = `loadtest_${__VU}_${Date.now()}@example.com`;

    const query = `
      mutation SignUp($email: String!, $password: String!, $name: String!) {
        signUp(input: { email: $email, password: $password, name: $name }) {
          authPayload { token }
          errors
        }
      }
    `;

    const start = Date.now();
    const response = graphql(query, {
      email: email,
      password: "testpassword123",
      name: `Load Test ${__VU}`,
    });
    authLatency.add(Date.now() - start);

    const body = JSON.parse(response.body);
    const success = body.data?.signUp?.authPayload?.token != null;

    check(response, {
      "signup successful": () => success,
    });
    errorRate.add(!success);
  });

  sleep(0.5);
}
