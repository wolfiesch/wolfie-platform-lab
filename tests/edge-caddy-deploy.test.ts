import { afterEach, describe, expect, test } from "bun:test";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Runs the remote half of scripts/deploy-caddy-k8s-health.sh against a local
// edge Caddyfile, with sudo and docker stubbed, to pin what the rewrite keeps.

const repo = join(import.meta.dir, "..");
const script = readFileSync(join(repo, "scripts/deploy-caddy-k8s-health.sh"), "utf8");
const remoteBody = script.match(/<<'REMOTE'\n([\s\S]*?)\nREMOTE\n/)?.[1];

const ompdocsBlock = `# BEGIN ompdocs
omp.wolfie.gg {
	import wolfsuite_fleet_log
	import wolfsuite_fleet_routes
	encode zstd gzip

	handle {
		root * /srv/static/ompdocs
		file_server
	}
}
# END ompdocs
`;

const retiredOmpBlock = `# BEGIN wolfie-platform-lab:omp
# Edge Caddy forwards OMP redirect handling to K3s Caddy.
omp.wolfie.gg {
	encode zstd gzip
	reverse_proxy 192.0.2.10:80 {
		header_down -Server
	}
}
# END wolfie-platform-lab:omp
`;

function edgeCaddyfile(ompBlock: string): string {
  return `{$HUB_DOMAIN} {
	respond "hub" 200
}

# BEGIN wolfie-platform-lab:k8s-health
k8s-health.wolfie.gg {
	reverse_proxy 192.0.2.10:80
}
# END wolfie-platform-lab:k8s-health

${ompBlock}
# BEGIN wolfie-platform-lab:freakoff
freakoff.wolfie.gg {
	reverse_proxy 192.0.2.10:80
}
# END wolfie-platform-lab:freakoff
`;
}

const scratchDirs: string[] = [];

afterEach(() => {
  for (const dir of scratchDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function edge(initial: string) {
  const dir = mkdtempSync(join(tmpdir(), "edge-caddy-deploy-"));
  scratchDirs.push(dir);
  const bin = join(dir, "bin");
  const fragments = join(dir, "fragments");
  const caddyfile = join(dir, "Caddyfile");
  const remote = join(dir, "remote.sh");
  cpSync(join(repo, "ops/caddy"), fragments, { recursive: true });
  mkdirSync(bin);
  writeFileSync(join(bin, "sudo"), '#!/bin/sh\nexec "$@"\n');
  writeFileSync(join(bin, "docker"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(bin, "sudo"), 0o755);
  chmodSync(join(bin, "docker"), 0o755);
  writeFileSync(remote, remoteBody ?? "");
  writeFileSync(caddyfile, initial);

  return {
    deploy() {
      return Bun.spawnSync({
        cmd: ["bash", remote],
        env: {
          ...process.env,
          PATH: `${bin}:${process.env.PATH}`,
          REMOTE_FRAGMENT_DIR: fragments,
          REMOTE_CADDYFILE: caddyfile,
          CADDY_CONTAINER: "stub",
          CADDY_IMAGE: "stub",
          HUB_DOMAIN: "hooks.example",
          MARKER_PREFIX: "wolfie-platform-lab:",
        },
        stderr: "pipe",
        stdout: "pipe",
      });
    },
    read: () => readFileSync(caddyfile, "utf8"),
  };
}

const count = (text: string, line: string) => text.split("\n").filter((l) => l === line).length;
const squeezeBlankLines = (text: string) => text.replace(/\n{3,}/g, "\n\n");

describe("edge Caddy deploy rewrite", () => {
  test("keeps the ompdocs block and the retired omp fragment stays gone across repeated deploys", () => {
    const host = edge(edgeCaddyfile(ompdocsBlock));

    const first = host.deploy();
    expect(first.exitCode).toBe(0);
    const afterFirst = host.read();
    expect(host.deploy().exitCode).toBe(0);
    const afterSecond = host.read();

    for (const text of [afterFirst, afterSecond]) {
      expect(text).toContain(ompdocsBlock);
      expect(count(text, "omp.wolfie.gg {")).toBe(1);
      expect(text).not.toContain("wolfie-platform-lab:omp");
      expect(count(text, "# BEGIN wolfie-platform-lab:k8s-health")).toBe(1);
      expect(count(text, "# BEGIN wolfie-platform-lab:freakoff")).toBe(1);
      expect(count(text, "k8s-health.wolfie.gg {")).toBe(1);
      expect(count(text, "freakoff.wolfie.gg {")).toBe(1);
    }
    expect(squeezeBlankLines(afterSecond)).toBe(squeezeBlankLines(afterFirst));
  });

  test("refuses to drop the retired omp block before the ompdocs cutover", () => {
    const initial = edgeCaddyfile(retiredOmpBlock);
    const host = edge(initial);

    const result = host.deploy();

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr.toString()).toContain("ompdocs");
    expect(host.read()).toBe(initial);
  });
});
