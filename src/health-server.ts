type HealthServerOptions = {
  serviceName: string;
  port?: number;
};

type JsonBody = Record<string, unknown>;

const startedAt = Date.now();

function jsonResponse(body: JsonBody, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      "cache-control": "no-store",
    },
  });
}

export function createHealthServer(options: HealthServerOptions): Bun.Server<undefined> {
  return Bun.serve({
    hostname: "0.0.0.0",
    port: options.port ?? 0,
    fetch(request) {
      const url = new URL(request.url);

      if (url.pathname === "/healthz") {
        return jsonResponse({
          status: "ok",
          service: options.serviceName,
          uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
        });
      }

      if (url.pathname === "/readyz") {
        return jsonResponse({
          status: "ready",
          checks: {
            server: "ok",
          },
        });
      }

      return jsonResponse({ error: "not_found" }, 404);
    },
  });
}
