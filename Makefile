.PHONY: test typecheck deploy deploy-api deploy-caddy verify-public argocd-diff argocd-apply

REMOTE_HOST ?= hostinger-devbox-ts
ARGOCD_KUSTOMIZE := gitops/platform/argocd

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

# Argo CD is bootstrapped outside Argo CD. Server-side apply keeps the same
# field manager ("kubectl") the original install used.
argocd-diff:
	ssh $(REMOTE_HOST) 'rm -rf /tmp/argocd-kustomize && mkdir -p /tmp/argocd-kustomize'
	scp -q $(ARGOCD_KUSTOMIZE)/kustomization.yaml $(REMOTE_HOST):/tmp/argocd-kustomize/
	ssh $(REMOTE_HOST) 'sudo k3s kubectl diff --server-side --force-conflicts -k /tmp/argocd-kustomize' || test $$? -eq 1

argocd-apply: argocd-diff
	ssh $(REMOTE_HOST) 'sudo k3s kubectl apply --server-side --force-conflicts -k /tmp/argocd-kustomize'
	ssh $(REMOTE_HOST) 'for r in sts/argocd-application-controller deploy/argocd-repo-server deploy/argocd-server deploy/argocd-applicationset-controller deploy/argocd-notifications-controller deploy/argocd-dex-server deploy/argocd-redis; do sudo k3s kubectl -n argocd rollout status $$r --timeout=180s || exit 1; done'
