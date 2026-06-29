import { afterEach, describe, expect, test } from "bun:test";
import { createHealthServer } from "../src/health-server";

const servers: Bun.Server<undefined>[] = [];

async function startTestServer(): Promise<string> {
  const server = createHealthServer({ serviceName: "test-health-api" });
  servers.push(server);
  return `http://127.0.0.1:${server.port}`;
}

afterEach(() => {
  for (const server of servers.splice(0)) {
    server.stop(true);
  }
});

describe("health API", () => {
  test("GET /healthz reports the service is alive", async () => {
    const baseUrl = await startTestServer();

    const response = await fetch(`${baseUrl}/healthz`);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe("ok");
    expect(body.service).toBe("test-health-api");
    expect(typeof body.uptimeSeconds).toBe("number");
  });

  test("GET /readyz reports readiness checks", async () => {
    const baseUrl = await startTestServer();

    const response = await fetch(`${baseUrl}/readyz`);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe("ready");
    expect(body.checks).toEqual({ server: "ok" });
  });

  test("unknown routes return JSON 404", async () => {
    const baseUrl = await startTestServer();

    const response = await fetch(`${baseUrl}/missing`);
    const body = await response.json();

    expect(response.status).toBe(404);
    expect(body.error).toBe("not_found");
  });
});
