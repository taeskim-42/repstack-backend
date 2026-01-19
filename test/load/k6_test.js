/**
 * RepStack Backend Load Test
 *
 * Run with: k6 run test/load/k6_test.js
 *
 * Scenarios:
 * 1. Health check baseline
 * 2. Authentication flow
 * 3. Workout session flow
 * 4. AI routine generation (rate limited)
 */

import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";

// Custom metrics
const errorRate = new Rate("errors");
const authLatency = new Trend("auth_latency");
const graphqlLatency = new Trend("graphql_latency");
const routineGenLatency = new Trend("routine_generation_latency");
const successfulLogins = new Counter("successful_logins");
const failedLogins = new Counter("failed_logins");

// Configuration
const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";

export const options = {
  // Test scenarios
  scenarios: {
    // Constant load for health checks
    health_check: {
      executor: "constant-vus",
      vus: 5,
      duration: "1m",
      exec: "healthCheck",
      tags: { scenario: "health" },
    },

    // Ramp up authentication load
    authentication: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: 20 },
        { duration: "1m", target: 20 },
        { duration: "30s", target: 0 },
      ],
      exec: "authenticationFlow",
      tags: { scenario: "auth" },
    },

    // Workout session operations
    workout_flow: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: 30 },
        { duration: "2m", target: 30 },
        { duration: "30s", target: 0 },
      ],
      exec: "workoutFlow",
      tags: { scenario: "workout" },
    },

    // AI routine generation (limited due to cost)
    routine_generation: {
      executor: "constant-arrival-rate",
      rate: 10, // 10 requests per timeUnit
      timeUnit: "1m", // per minute
      duration: "2m",
      preAllocatedVUs: 5,
      exec: "routineGeneration",
      tags: { scenario: "ai" },
    },
  },

  // Thresholds for pass/fail criteria
  thresholds: {
    http_req_duration: ["p(95)<500", "p(99)<1000"], // 95% under 500ms, 99% under 1s
    errors: ["rate<0.05"], // Error rate under 5%
    auth_latency: ["p(95)<300"],
    graphql_latency: ["p(95)<400"],
    routine_generation_latency: ["p(95)<30000"], // AI can take up to 30s
  },
};

// GraphQL helper
function graphql(query, variables = {}, token = null) {
  const headers = {
    "Content-Type": "application/json",
  };

  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const payload = JSON.stringify({
    query: query,
    variables: variables,
  });

  const start = Date.now();
  const response = http.post(`${BASE_URL}/graphql`, payload, { headers });
  graphqlLatency.add(Date.now() - start);

  return response;
}

// Scenario: Health Check
export function healthCheck() {
  group("Health Check", () => {
    const response = http.get(`${BASE_URL}/health`);

    check(response, {
      "health status is 200": (r) => r.status === 200,
      "health returns ok": (r) => JSON.parse(r.body).status === "ok",
    });

    errorRate.add(response.status !== 200);
  });

  sleep(0.5);
}

// Scenario: Authentication Flow
export function authenticationFlow() {
  const email = `loadtest_${__VU}_${Date.now()}@example.com`;
  const password = "testpassword123";

  group("Sign Up", () => {
    const signUpQuery = `
      mutation SignUp($email: String!, $password: String!, $name: String!) {
        signUp(input: { email: $email, password: $password, name: $name }) {
          authPayload {
            token
            user { id email }
          }
          errors
        }
      }
    `;

    const start = Date.now();
    const response = graphql(signUpQuery, {
      email: email,
      password: password,
      name: `Load Test User ${__VU}`,
    });
    authLatency.add(Date.now() - start);

    const body = JSON.parse(response.body);
    const success = body.data?.signUp?.authPayload?.token != null;

    check(response, {
      "signup successful": () => success,
      "no signup errors": () => body.data?.signUp?.errors?.length === 0,
    });

    errorRate.add(!success);

    if (success) {
      successfulLogins.add(1);
      return body.data.signUp.authPayload.token;
    }
    return null;
  });

  sleep(1);

  group("Sign In", () => {
    const signInQuery = `
      mutation SignIn($email: String!, $password: String!) {
        signIn(input: { email: $email, password: $password }) {
          authPayload {
            token
            user { id email }
          }
          errors
        }
      }
    `;

    const start = Date.now();
    const response = graphql(signInQuery, {
      email: email,
      password: password,
    });
    authLatency.add(Date.now() - start);

    const body = JSON.parse(response.body);
    const success = body.data?.signIn?.authPayload?.token != null;

    check(response, {
      "signin successful": () => success,
    });

    errorRate.add(!success);

    if (success) {
      successfulLogins.add(1);
    } else {
      failedLogins.add(1);
    }
  });

  sleep(1);
}

// Scenario: Workout Flow
export function workoutFlow() {
  // First, create a test user and get token
  const email = `workout_${__VU}_${Date.now()}@example.com`;
  const password = "testpassword123";

  const signUpQuery = `
    mutation SignUp($email: String!, $password: String!, $name: String!) {
      signUp(input: { email: $email, password: $password, name: $name }) {
        authPayload { token }
        errors
      }
    }
  `;

  const signUpResponse = graphql(signUpQuery, {
    email: email,
    password: password,
    name: `Workout User ${__VU}`,
  });

  const token = JSON.parse(signUpResponse.body).data?.signUp?.authPayload
    ?.token;
  if (!token) {
    errorRate.add(1);
    return;
  }

  group("Start Workout Session", () => {
    const startSessionQuery = `
      mutation StartWorkoutSession($name: String) {
        startWorkoutSession(input: { name: $name }) {
          workoutSession { id name active }
          errors
        }
      }
    `;

    const response = graphql(
      startSessionQuery,
      { name: "Load Test Workout" },
      token
    );

    const body = JSON.parse(response.body);
    const sessionId = body.data?.startWorkoutSession?.workoutSession?.id;

    check(response, {
      "session created": () => sessionId != null,
    });

    errorRate.add(!sessionId);

    if (sessionId) {
      // Add some workout sets
      group("Add Workout Sets", () => {
        const exercises = ["Bench Press", "Squat", "Deadlift"];

        for (const exercise of exercises) {
          const addSetQuery = `
            mutation AddWorkoutSet($sessionId: ID!, $exerciseName: String!, $weight: Float, $reps: Int) {
              addWorkoutSet(input: {
                sessionId: $sessionId,
                exerciseName: $exerciseName,
                weight: $weight,
                reps: $reps
              }) {
                workoutSet { id }
                errors
              }
            }
          `;

          const setResponse = graphql(
            addSetQuery,
            {
              sessionId: sessionId,
              exerciseName: exercise,
              weight: 60 + Math.random() * 40,
              reps: 8 + Math.floor(Math.random() * 4),
            },
            token
          );

          check(setResponse, {
            "set added": (r) =>
              JSON.parse(r.body).data?.addWorkoutSet?.workoutSet?.id != null,
          });

          sleep(0.5);
        }
      });

      // End session
      group("End Workout Session", () => {
        const endSessionQuery = `
          mutation EndWorkoutSession($id: ID!) {
            endWorkoutSession(input: { id: $id }) {
              workoutSession { id completed }
              errors
            }
          }
        `;

        const response = graphql(endSessionQuery, { id: sessionId }, token);

        check(response, {
          "session ended": (r) =>
            JSON.parse(r.body).data?.endWorkoutSession?.workoutSession
              ?.completed === true,
        });
      });
    }
  });

  sleep(2);
}

// Scenario: AI Routine Generation
export function routineGeneration() {
  // Create user first
  const email = `routine_${__VU}_${Date.now()}@example.com`;

  const signUpQuery = `
    mutation SignUp($email: String!, $password: String!, $name: String!) {
      signUp(input: { email: $email, password: $password, name: $name }) {
        authPayload { token }
        errors
      }
    }
  `;

  const signUpResponse = graphql(signUpQuery, {
    email: email,
    password: "testpassword123",
    name: `Routine User ${__VU}`,
  });

  const token = JSON.parse(signUpResponse.body).data?.signUp?.authPayload
    ?.token;

  group("Generate Routine", () => {
    const generateQuery = `
      mutation GenerateRoutine($level: String!, $week: Int!, $day: Int!) {
        generateRoutine(input: { level: $level, week: $week, day: $day }) {
          routine {
            workoutType
            exercises { exerciseName sets reps }
          }
          errors
          isMock
        }
      }
    `;

    const levels = ["beginner", "intermediate", "advanced"];
    const level = levels[Math.floor(Math.random() * levels.length)];
    const week = 1 + Math.floor(Math.random() * 4);
    const day = 1 + Math.floor(Math.random() * 5);

    const start = Date.now();
    const response = graphql(
      generateQuery,
      { level: level, week: week, day: day },
      token
    );
    routineGenLatency.add(Date.now() - start);

    const body = JSON.parse(response.body);

    check(response, {
      "routine generated": () => body.data?.generateRoutine?.routine != null,
      "has exercises": () =>
        body.data?.generateRoutine?.routine?.exercises?.length > 0,
    });

    errorRate.add(body.data?.generateRoutine?.routine == null);
  });

  sleep(5); // Longer sleep for AI endpoints
}

// Summary report
export function handleSummary(data) {
  return {
    "load-test-summary.json": JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: " ", enableColors: true }),
  };
}

function textSummary(data, options) {
  // Simple text summary
  let summary = "\n=== LOAD TEST SUMMARY ===\n\n";

  summary += `Total Requests: ${data.metrics.http_reqs.values.count}\n`;
  summary += `Failed Requests: ${data.metrics.http_req_failed?.values.passes || 0}\n`;
  summary += `Avg Response Time: ${data.metrics.http_req_duration.values.avg.toFixed(2)}ms\n`;
  summary += `P95 Response Time: ${data.metrics.http_req_duration.values["p(95)"].toFixed(2)}ms\n`;
  summary += `P99 Response Time: ${data.metrics.http_req_duration.values["p(99)"].toFixed(2)}ms\n`;

  if (data.metrics.errors) {
    summary += `Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%\n`;
  }

  summary += "\n=== THRESHOLDS ===\n";
  for (const [name, threshold] of Object.entries(data.thresholds || {})) {
    const status = threshold.ok ? "✓ PASS" : "✗ FAIL";
    summary += `${status}: ${name}\n`;
  }

  return summary;
}
