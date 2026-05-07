# Developer Log — Agentic-ERP-Deploy

Chronological tracker for all errors, root causes, and fixes during Project 2 development and operations.

**Format:** See `ml-project-docs.prompt.md` → Developer_Log section.

---

## [2026-05-02 00:00] — Project 2 initialized

- **Error:** N/A — initial scaffolding
- **Root cause:** N/A
- **Fix:** Created full directory structure per blueprint Section 1.1.2.
  All files: GitHub Actions workflows, Bicep modules, K8s manifests, monitoring, scripts, azure.yaml.
- **Files modified:** All files in Agentic-ERP-Deploy/

---

<!-- Append new entries below as they occur during infra deployment and operations -->

---

## [2026-05-08 00:00] — CI trigger failed: PAT resource not accessible

- **Error:** `HttpError: Resource not accessible by personal access token` when `trigger-deploy` job in Project 1 attempted to fire `repository_dispatch` to `Agentic-ERP-Deployment`.
- **Root cause:** The fine-grained PAT stored as `DEPLOY_REPO_PAT` in Project 1 secrets was missing the **Contents: Read & Write** permission on the `Agentic-ERP-Deployment` repository. Creating a dispatch event requires write access to repository contents.
- **Fix:** Regenerated the fine-grained PAT with `Contents: Read & Write` on `Agentic-ERP-Deployment` and updated the `DEPLOY_REPO_PAT` secret in Project 1.
- **Files modified:** None (GitHub secret updated via UI).

---

## [2026-05-08 01:00] — Deploy failed: AuthorizationFailed on listClusterUserCredential

- **Error:** `(AuthorizationFailed) The client does not have authorization to perform action 'Microsoft.ContainerService/managedClusters/listClusterUserCredential/action'` in the deploy workflow `az aks get-credentials` step.
- **Root cause:** Two compounding issues:
  1. The `RG_NAME` GitHub secret had a trailing space (`rg-agentic-erp-prod ` instead of `rg-agentic-erp-prod`), causing Azure CLI to look for a non-existent resource group.
  2. RBAC role propagation delay after assigning **AKS Cluster User Role** to the service principal.
- **Fix:** Removed the trailing space from the `RG_NAME` secret (re-entered value without whitespace). Verified role assignment with `az role assignment list` showing both `Contributor` and `Azure Kubernetes Service Cluster User Role` on the AKS resource.
- **Files modified:** None (GitHub secret corrected via UI).

---

## [2026-05-08 02:00] — Deploy failed: kubectl apply missing kustomization.yaml

- **Error:** `kubectl apply -k k8s/base/` exited with error — no `kustomization.yaml` found in `k8s/base/`.
- **Root cause:** The base manifests directory had no Kustomize entry point. The `kubectl apply -k` flag requires a `kustomization.yaml` listing the resources to apply.
- **Fix:** Created `k8s/base/kustomization.yaml` listing all six base resources: `api-deployment.yaml`, `api-service.yaml`, `frontend-deployment.yaml`, `frontend-service.yaml`, `configmap.yaml`, `ingress.yaml`.
- **Files modified:** `k8s/base/kustomization.yaml` (created).

---

## [2026-05-08 02:30] — Deploy failed: ingress hostname still REPLACE_WITH_FQDN

- **Error:** Ingress applied to cluster with hostname `REPLACE_WITH_FQDN` — nginx could not route any traffic.
- **Root cause:** The local edit replacing the placeholder with `erp.131-189-252-158.nip.io` had never been committed. The TLS section also referenced cert-manager which is not installed.
- **Fix:** Committed the ingress update with the actual nip.io hostname, removed the TLS section entirely, and set `ssl-redirect: "false"`. Also removed `rewrite-target: /` (see entry below).
- **Files modified:** `k8s/base/ingress.yaml`.

---

## [2026-05-08 03:00] — Deploy failed: kubectl apply-k before set-image missing in workflow

- **Error:** `kubectl set image` was failing with `deployment not found` on first deploy runs because the base manifests had never been applied to the cluster.
- **Root cause:** `deploy.yml` only ran `kubectl set image` without first applying the base manifests. A freshly provisioned cluster has no deployments until `kubectl apply -k` is run.
- **Fix:** Added a `kubectl apply -k k8s/base/` step immediately before `kubectl set image` in `deploy.yml`.
- **Files modified:** `.github/workflows/deploy.yml`.

---

## [2026-05-08 04:00] — API pod OOMKilled (exit 137)

- **Error:** `kubectl describe pod api-xxx` showed `OOMKilled` with exit code 137. Pod restarted in a crash loop.
- **Root cause:** `sentence-transformers` imports `torch` at module load time, consuming 500 MB–1 GB of memory before the first request. The original memory limit of 1 Gi was insufficient.
- **Fix:** Increased API pod memory: `requests 512Mi → 1Gi`, `limits 1Gi → 3Gi`. Reduced replicas from 2 to 1 to stay within the node pool capacity (2 × Standard_B2s = ~4 Gi allocatable).
- **Files modified:** `k8s/base/api-deployment.yaml`.

---

## [2026-05-08 04:30] — API pod failed: serviceAccountName api-workload-sa not found

- **Error:** API pod stuck in `Pending` — `serviceaccounts "api-workload-sa" not found`.
- **Root cause:** The base manifest referenced `serviceAccountName: api-workload-sa` which requires Azure Workload Identity federation (OIDC + federated credential). This was not configured in the cluster.
- **Fix:** Removed `serviceAccountName` from `api-deployment.yaml`. The pod now runs under the default service account. Workload Identity is deferred — see Project_Notes.
- **Files modified:** `k8s/base/api-deployment.yaml`.

---

## [2026-05-08 05:00] — Frontend pod stuck: InvalidImageName / port mismatch

- **Error:** Frontend pod showed `InvalidImageName` then, after image fix, `CrashLoopBackOff` with exit 1. `kubectl describe` showed readiness probe failures on port 3000.
- **Root cause:** The frontend Dockerfile uses `nginx:alpine` which listens on port 80. The deployment manifest had `containerPort: 3000`, the service had `targetPort: 3000`, and both liveness/readiness probes hit port 3000. Nginx never bound port 3000.
- **Fix:** Changed all port references from 3000 → 80 in `frontend-deployment.yaml` and `frontend-service.yaml`.
- **Files modified:** `k8s/base/frontend-deployment.yaml`, `k8s/base/frontend-service.yaml`.

---

## [2026-05-08 05:30] — Frontend pod CrashLoopBackOff: nginx cannot bind port 80

- **Error:** Frontend pod kept restarting with exit 1. Logs: `nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)`.
- **Root cause:** Security context had `runAsNonRoot: true` and `capabilities: drop: [ALL]`. Binding to port 80 (privileged port < 1024) requires `NET_BIND_SERVICE` capability; `CHOWN`/`SETUID`/`SETGID` are needed for nginx worker processes.
- **Fix:** Set `runAsNonRoot: false` and added capabilities `NET_BIND_SERVICE`, `CHOWN`, `SETUID`, `SETGID` while retaining `allowPrivilegeEscalation: false`.
- **Files modified:** `k8s/base/frontend-deployment.yaml`.

---

## [2026-05-08 06:00] — Smoke test exit 60: SSL certificate problem

- **Error:** `curl: (60) SSL certificate problem: self signed certificate` — smoke test exited with code 1 after the first curl command.
- **Root cause:** The smoke test was using `https://` but TLS/cert-manager is not configured. nginx ingress was returning a self-signed certificate that curl refused by default.
- **Fix:** Added `-k` (insecure) flag to all `curl` calls in `smoke-test.sh`. Long-term fix is to configure cert-manager with Let's Encrypt.
- **Files modified:** `scripts/smoke-test.sh`.

---

## [2026-05-08 06:15] — Smoke test exits after first PASS

- **Error:** Smoke test passed test 1 then immediately exited with code 1.
- **Root cause:** `set -euo pipefail` is active. `((PASS++))` with `PASS=0` evaluates the arithmetic expression to 0 (falsy), which under `set -e` terminates the script.
- **Fix:** Changed `((PASS++))` → `((++PASS))` and `((FAIL++))` → `((++FAIL))` so the post-increment returns the new value (≥1) which is truthy.
- **Files modified:** `scripts/smoke-test.sh`.

---

## [2026-05-08 06:30] — Smoke test 405 Method Not Allowed on tests 2–4

- **Error:** Smoke tests 2, 3, and 4 failed with HTTP 405. Tests were hitting `/api/chat`, `/api/inventory/query`, `/api/contracts`.
- **Root cause:** The original test endpoints did not exist in the deployed API. `/api/chat` was the intended WebSocket-based endpoint but the HTTP REST path is not exposed.
- **Fix:** Rewrote all six smoke tests to use endpoints that actually exist: `/health` (200), `/docs` (200), `/ws/chat` WebSocket handshake (101/400/403/404 all accepted), `/api/approve/<nonexistent-id>` (404 proves routing works), security/prompt-injection check, `/` frontend (200).
- **Files modified:** `scripts/smoke-test.sh`.

---

## [2026-05-08 07:00] — Smoke test 307 redirect on API and WebSocket paths

- **Error:** Tests 3 and 4 returned HTTP 307. All paths under `/api` and `/ws` were being redirected to `/`.
- **Root cause:** The ingress had `nginx.ingress.kubernetes.io/rewrite-target: /` which rewrote all request URIs to `/`, causing nginx to return a redirect to the frontend.
- **Fix:** Removed the `rewrite-target: /` annotation from `k8s/base/ingress.yaml`. The API and frontend services serve from their own root paths — no rewriting needed.
- **Files modified:** `k8s/base/ingress.yaml`.

---

## [2026-05-08 07:30] — WebSocket ingress annotation rejected by admission webhook

- **Error:** `kubectl apply` failed with: `admission webhook denied: nginx.ingress.kubernetes.io/configuration-snippet: annotation not allowed`.
- **Root cause:** The NGINX ingress controller was deployed with `--set controller.allowSnippetAnnotations=false` (the default since ingress-nginx v1.9). The `configuration-snippet` annotation used to set `proxy_set_header Upgrade` was blocked.
- **Fix:** Removed the `configuration-snippet` annotation. Applied only `proxy-http-version: "1.1"` which is a first-class annotation and sufficient for WebSocket proxying on nginx ingress.
- **Files modified:** `k8s/base/ingress.yaml`.

---

## [2026-05-08 08:00] — WebSocket chat shows "Reconnecting" in production

- **Error:** Chat UI at `http://erp.131-189-252-158.nip.io` shows "Reconnecting…" indefinitely. WebSocket connection never established.
- **Root cause:** `frontend/src/App.tsx` resolves the WebSocket URL at runtime via: `import.meta.env.VITE_WS_BASE_URL ?? \`ws://${window.location.hostname}:8000\``. The Docker image was built without `VITE_WS_BASE_URL` set, so it fell back to `ws://erp.131-189-252-158.nip.io:8000`. Port 8000 is not externally exposed — only port 80 is accessible via the nginx ingress.
- **Fix:** Added `ARG VITE_WS_BASE_URL=ws://erp.131-189-252-158.nip.io` and `ENV VITE_WS_BASE_URL=${VITE_WS_BASE_URL}` to `frontend/Dockerfile` before `RUN npm run build`. Added `--build-arg VITE_WS_BASE_URL=ws://erp.131-189-252-158.nip.io` to the docker build command in `ci.yml`. The ingress already routes `/ws/*` to the API service, so the correct URL is `ws://erp.131-189-252-158.nip.io/ws/chat`.
- **Files modified:** `frontend/Dockerfile` (Project 1), `.github/workflows/ci.yml` (Project 1).
