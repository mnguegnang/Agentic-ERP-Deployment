# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Does

This is **Project 2 of 2** — it owns all infrastructure-as-code, Kubernetes manifests, deployment workflows, and monitoring for the Agentic ERP Supply Chain Copilot. It **never builds application code**; it only consumes pre-built container images from Azure Container Registry (ACR) that are built and pushed by Project 1 (`Agentic-ERP-SupplyChain-Copilot`).

## Required Tools

| Tool | Min Version |
|------|-------------|
| Azure CLI (`az`) | 2.65 |
| Azure Developer CLI (`azd`) | 1.11 |
| `kubectl` | 1.31 |
| Kustomize | 5.4 (bundled with kubectl) |
| Helm | 3.16 |
| `jq` | 1.7 |

## Key Commands

### Provision infrastructure
```bash
cp .env.example .env         # fill in Azure credentials + resource names
source .env
az login
az group create --name "$RG_NAME" --location eastus
./scripts/provision.sh production   # or: staging
```
`provision.sh` runs a Bicep what-if preview and prompts for confirmation before applying. It also applies Kubernetes manifests via Kustomize and deploys the OTel collector.

### Validate Bicep templates (dry run)
```bash
az deployment group validate \
  --resource-group "$RG_NAME" \
  --template-file infra/main.bicep \
  --parameters "infra/parameters/production.bicepparam" \
  --parameters acrName="$ACR_NAME"
```

### Deploy application (manual)
```bash
# Via GitHub Actions (preferred):
gh workflow run deploy.yml -f image_tag=<COMMIT_SHA>

# Emergency direct kubectl:
kubectl set image deployment/api api=<ACR>.azurecr.io/api:<TAG> --namespace default
kubectl set image deployment/frontend frontend=<ACR>.azurecr.io/frontend:<TAG> --namespace default
kubectl rollout status deployment/api --timeout=120s
kubectl rollout status deployment/frontend --timeout=120s
```

### Run smoke tests
```bash
SMOKE_BASE_URL=https://your-domain ./scripts/smoke-test.sh
```
All 6 tests must pass (health, KG query, MCNF solver, CRAG contract, prompt injection blocked, WebSocket reachable).

### Rollback
```bash
kubectl rollout undo deployment/api
kubectl rollout undo deployment/frontend
# Revert to specific image:
kubectl set image deployment/api api=<ACR>/<image>:<old-tag>
```

## Architecture

```
Project 1 CI (push to main)
  ├─ lint + test + red-team
  ├─ build + push images → ACR
  └─ repository_dispatch ──────────→ deploy.yml (this repo)
                                         ├─ environment: production  (manual approval gate)
                                         ├─ kubectl set image → AKS
                                         └─ smoke-test job
```

### Azure Resources (target ~$116/mo)

| Resource | SKU | Purpose |
|----------|-----|---------|
| AKS | Standard_B2s × 2 | Container orchestration |
| PostgreSQL Flexible | B1ms | ERP data + pgvector |
| Cosmos DB (Gremlin) | Free tier | Knowledge graph |
| Azure AI Search | Free tier | Full-text search |
| Container Registry | Basic | Image storage |
| Redis Cache | Basic C0 | Semantic cache + HiTL |
| App Insights + Log Analytics | PerGB2018 | Traces, metrics, alerts |

### Bicep module structure

`infra/main.bicep` is the root orchestrator. Each Azure resource has its own module under `infra/modules/`. Parameters live in `infra/parameters/{dev,prod}.bicepparam`. The `acr.bicep` module references an existing ACR (from Project 1) rather than creating a new one — it only attaches the AKS role assignment.

### Kubernetes manifests

`k8s/base/` contains base manifests for both deployments (`api`, `frontend`), services, ConfigMap, and Ingress. Kustomize overlays in `k8s/overlays/{staging,production}/` patch environment-specific values. The deploy workflow uses `kubectl set image` to inject the correct image tag at deploy time — the base manifests use `ACR_PLACEHOLDER`.

The Ingress routes `/api/*` and `/ws/*` to the `api` service and `/*` to `frontend`. The `REPLACE_WITH_FQDN` hostname placeholder must be set in the overlay before applying.

### CI/CD workflows

- `deploy.yml` — triggered by `repository_dispatch` from Project 1 or manually via `workflow_dispatch`. Requires GitHub environment `production` (manual approval gate).
- `infra.yml` — manual-only, provisions or updates Azure infrastructure. Supports a `what_if` dry-run mode.

## Known Setup Requirements

1. **NGINX Ingress Controller** — installed via Helm, not Bicep:
   ```bash
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm repo update
   helm install ingress-nginx ingress-nginx/ingress-nginx \
     --namespace ingress-nginx --create-namespace
   ```

2. **TLS / cert-manager** — not automated; install cert-manager and create a ClusterIssuer for Let's Encrypt, then update the Ingress overlay.

3. **Redis access key** — not output by Bicep; retrieve with `az redis list-keys` and store in the K8s Secret `app-secrets`.

4. **Ingress FQDN** — the `erp.131-189-252-158.nip.io` hostname in `k8s/base/ingress.yaml` is a placeholder; set the real domain in the Kustomize overlay.

5. **`app-secrets` K8s Secret** — must be created manually with database credentials, Redis key, and App Insights connection string before deploying pods.

## Important Files

| File | Purpose |
|------|---------|
| `Developer_Log.md` | Chronological error/fix tracker — append all incidents here |
| `Project_Notes.md` | Architectural decisions and deviations from the blueprint |
| `.env.example` | All required environment variables with descriptions |
| `azure.yaml` | `azd` project definition (no services to build — images come from ACR) |
| `monitoring/dashboards/production.json` | Grafana dashboard — import manually |
| `monitoring/otel-collector.yaml` | OTel Collector DaemonSet (forwards traces to App Insights) |
