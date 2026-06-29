.PHONY: test typecheck deploy deploy-api deploy-caddy verify-public

test:
	bun test

typecheck:
	bun run typecheck

deploy: deploy-api deploy-caddy verify-public

deploy-api:
	./scripts/deploy-health-api.sh

deploy-caddy:
	./scripts/deploy-caddy-k8s-health.sh

verify-public:
	curl -fsS --resolve k8s-health.wolfie.gg:443:193.46.198.110 https://k8s-health.wolfie.gg/healthz
	curl -fsS --connect-timeout 5 http://193.46.198.110:30080/healthz || test $$? -eq 28
