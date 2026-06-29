import { createHealthServer } from "./health-server";

const port = Number(process.env.PORT ?? "3000");
const serviceName = process.env.SERVICE_NAME ?? "wolfie-health-api";
const server = createHealthServer({ port, serviceName });

console.log(`${serviceName} listening on http://0.0.0.0:${server.port}`);
