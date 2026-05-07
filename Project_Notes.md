# Project Notes — Agentic-ERP-Deploy

Architectural decisions, deviations from the PI Blueprint, known technical debt, and scaling limits.

**Format:** See `ml-project-docs.prompt.md` → Project_Notes section.

---

## Blueprint Reference

- **Blueprint:** `Agentic_Decision_Intelligence_Implementation_Blueprint.md`
- **Stage:** 7 — E2E Deployment
- **Section references:** 1.1.2 (repo structure), 7.1–7.7 (deployment pipeline, Bicep, rollback)
- **Budget:** $116/mo target, $170 ceiling

---

## Initial Assumptions (2026-05-02)

1. **ACR pre-exists**: The Azure Container Registry is created as part of this Bicep deployment (`infra/modules/acr.bicep`). If the ACR was manually pre-created by the user, the `acr.bicep` module will create a duplicate unless the name matches. Operator must verify before running `provision.sh`.

2. **Neo4j → Cosmos DB Gremlin**: The blueprint specifies Neo4j for local dev (docker-compose) and Cosmos DB Gremlin API for production. The `cosmosdb.bicep` module provisions the Gremlin database. The application `config.yaml` in Project 1 must be updated to use `GREMLIN_URI` when `APP_ENV=production`.

3. **Domain name not yet set**: The ingress YAML uses `REPLACE_WITH_FQDN` placeholder. The operator must set the actual FQDN in the Kustomize overlays (`k8s/overlays/staging/kustomization.yaml` and `k8s/overlays/production/kustomization.yaml`) before applying manifests.

4. **TLS not automated**: cert-manager is recommended (see README) but not provisioned by Bicep. Operator must install cert-manager and create a ClusterIssuer for Let's Encrypt. This is a known setup step, not a deviation.

5. **NGINX Ingress Controller not in Bicep**: Installed via Helm (see README Step 4). Deliberate choice — Bicep manages Azure resources only; cluster-level controllers are Helm-managed per industry convention.

6. **Redis `redisKey` parameter**: The `redis.bicep` module creates the Redis cache but does not use the `redisKey` parameter (Azure generates the key on creation). The parameter is wired through `main.bicep` for forward-compatibility but currently unused. The access key must be retrieved from Azure Portal or via `az redis list-keys` and stored in the K8s Secret `app-secrets`.

---

## Deviations from Blueprint

### DEV-01 — nip.io used instead of a real domain (2026-05-08)
- **Blueprint intent:** Ingress hostname should be a real FQDN (e.g., `erp.yourdomain.com`) with TLS via cert-manager and Let's Encrypt.
- **Actual:** Using `erp.131-189-252-158.nip.io` (a DNS wildcard service that resolves to the AKS load balancer IP). TLS section removed from ingress entirely. HTTP only.
- **Reason:** Azure credits expiring same day; no custom domain registered; cert-manager not installed. Portfolio demo does not require HTTPS.
- **Debt:** Install cert-manager, create ClusterIssuer, add TLS section back to ingress overlay before any real-world use.

### DEV-02 — Workload Identity (pod identity) not configured (2026-05-08)
- **Blueprint intent:** API pod should use Azure Workload Identity (`serviceAccountName: api-workload-sa`) with a federated credential for keyless Azure SDK authentication.
- **Actual:** `serviceAccountName` removed from `api-deployment.yaml`. Pod runs under the default service account. Azure SDK calls use credentials supplied via `app-secrets` environment variables instead.
- **Reason:** Setting up OIDC federation (OIDC issuer URL, federated credential, managed identity binding) requires additional provisioning steps that were out of scope for the demo deadline.
- **Debt:** Follow the Workload Identity setup guide; re-add `serviceAccountName: api-workload-sa` and remove credential env vars from `app-secrets` for the relevant Azure SDK calls.

### DEV-03 — API replicas reduced to 1 (2026-05-08)
- **Blueprint intent:** `api-deployment.yaml` specifies 2 replicas and `topologySpreadConstraints` to distribute across nodes.
- **Actual:** Replicas set to 1, `topologySpreadConstraints` removed.
- **Reason:** Each API replica requires ≥1 Gi memory (torch/sentence-transformers). With a 2-node pool of Standard_B2s (≈2 Gi allocatable per node), running 2 replicas exhausted memory and caused OOMKill on both. Running 1 replica allows the API to start reliably.
- **Debt:** Upgrade node pool SKU (e.g., Standard_D2s_v3 with 8 Gi) before scaling to 2+ replicas.

### DEV-04 — Cosmos DB Gremlin not provisioned (2026-05-08)
- **Blueprint intent:** `infra/modules/cosmosdb.bicep` provisions a Cosmos DB Gremlin account for the knowledge graph in production.
- **Actual:** `az cosmosdb create` failed with `ServiceUnavailable` due to high demand in East US. Cosmos DB was never provisioned. The application falls back to the Neo4j connection configured in `app-secrets` (bolt protocol, pointing to a placeholder if not overridden).
- **Reason:** Azure region capacity constraint at time of deployment.
- **Debt:** Retry provisioning in a different region (e.g., West Europe or West US 2), update `GREMLIN_URI` in `app-secrets`, and verify application Gremlin client connection.

### DEV-05 — NGINX configuration-snippet annotation disabled (2026-05-08)
- **Blueprint intent:** WebSocket proxying via `configuration-snippet` annotation to set `proxy_set_header Upgrade` and `proxy_set_header Connection "Upgrade"`.
- **Actual:** `configuration-snippet` annotation removed. Only `proxy-http-version: "1.1"` is set.
- **Reason:** The ingress-nginx controller (v1.9+) ships with `allowSnippetAnnotations=false` by default. The admission webhook rejected the snippet annotation. `proxy-http-version: "1.1"` is sufficient for WebSocket proxying on nginx ingress — the controller handles the Upgrade headers internally for HTTP/1.1.
- **Debt:** If custom nginx directives are needed in the future, reinstall ingress-nginx with `--set controller.allowSnippetAnnotations=true` (document the security implications).

### DEV-06 — VITE_WS_BASE_URL baked in at build time (2026-05-08)
- **Blueprint intent:** Frontend environment configuration is expected to be provided at runtime via ConfigMap/environment variables.
- **Actual:** `VITE_WS_BASE_URL=ws://erp.131-189-252-158.nip.io` is passed as a Docker build argument and baked into the Vite bundle at image build time. The value is hardcoded to the nip.io hostname.
- **Reason:** Vite replaces `import.meta.env.*` at build time — these are not runtime environment variables. The running nginx container cannot inject them after the JavaScript bundle is compiled.
- **Debt:** For a proper multi-environment setup, implement runtime env injection (e.g., an `env-config.js` file generated by a container entrypoint script and loaded via `<script>` in `index.html`), or maintain per-environment Docker build args passed through CI matrix.

### DEV-07 — kustomization.yaml added to k8s/base (2026-05-08)
- **Blueprint intent:** `k8s/base/` was structured as a Kustomize base but `kustomization.yaml` was not scaffolded in the initial commit.
- **Actual:** Created `k8s/base/kustomization.yaml` listing all six base resources. The deploy workflow uses `kubectl apply -k k8s/base/` to idempotently apply all manifests before running `kubectl set image`.
- **Reason:** `kubectl apply -k` requires the file; without it the deploy step failed on first run against a fresh cluster.

---

<!-- Append new deviation entries below as they occur -->
