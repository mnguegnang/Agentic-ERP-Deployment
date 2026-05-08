# Agentic-ERP-Deploy

> **Project 2 of 2** — Infrastructure, Kubernetes Manifests, and Deployment Workflows  
> Companion application repo: [`Agentic-ERP-SupplyChain-Copilot`](https://github.com/Gabin-Maxime/Agentic-ERP-SupplyChain-Copilot) (Project 1)  
> Live at: `http://erp.131-189-252-158.nip.io`

This repository owns all infrastructure-as-code, Kubernetes manifests, deployment workflows, and production monitoring for the Agentic ERP Supply Chain Copilot. It **never builds application code** — it consumes container images built and pushed to Azure Container Registry (ACR) by Project 1's CI pipeline.

---

## Prerequisites

### Gate: Dev-Complete (M8)

Do not start Project 2 until Project 1's M8 gate has passed:

- All 7 solver unit tests green
- Full agent eval: intent accuracy ≥ 90%, tool precision ≥ 95%
- Red-team: 0% injection success
- Docker Compose boots all 5 services
- Video demo recorded

### Required Tools

| Tool | Version | Install |
|------|---------|---------|
| Azure CLI | ≥ 2.65 | `curl -sL https://aka.ms/InstallAzureCLIDeb \| bash` |
| azd CLI | ≥ 1.11 | `curl -fsSL https://aka.ms/install-azd.sh \| bash` |
| kubectl | ≥ 1.31 | `az aks install-cli` |
| Kustomize | ≥ 5.4 | bundled with kubectl |
| Helm | ≥ 3.16 | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |
| jq | ≥ 1.7 | `sudo apt-get install jq` |

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/Gabin-Maxime/Agentic-ERP-Deploy.git
cd Agentic-ERP-Deploy
cp .env.example .env
# Edit .env: AZURE credentials, ACR_NAME, RG_NAME, AKS_NAME
```

### 2. Create the Azure resource group

```bash
source .env
az login
az group create --name "$RG_NAME" --location eastus
```

### 3. Provision infrastructure

```bash
./scripts/provision.sh production
# Runs az deployment group create with Bicep templates.
# Shows a what-if diff and prompts for confirmation before applying.
# Automatically fetches AKS credentials on success.
```

Estimated provisioning time: ~8 minutes.  
Estimated monthly cost: ~$116 (within $170 budget).

### 4. Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

Get the external IP assigned to the ingress LoadBalancer:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  --output jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 5. Create the `app-secrets` Kubernetes Secret

Before applying manifests, create the secret that all pods depend on:

```bash
kubectl create secret generic app-secrets \
  --from-literal=DATABASE_URL="postgresql+asyncpg://erp:<pass>@<pg-host>:5432/erp" \
  --from-literal=NEO4J_URI="bolt://neo4j:7687" \
  --from-literal=NEO4J_USER="neo4j" \
  --from-literal=NEO4J_PASSWORD="erp_neo4j_prod" \
  --from-literal=REDIS_URL="redis://redis:6379/0" \
  --from-literal=GITHUB_TOKEN="<pat>" \
  --from-literal=JWT_SECRET_KEY="<secret>"
```

### 6. Apply Kubernetes manifests

```bash
kubectl apply -k k8s/base/
```

> **Note:** `kubectl apply -k` resets image references to `ACR_PLACEHOLDER`. Always follow with `kubectl set image` (Step 7).

### 7. Deploy the application

Deployment is normally triggered automatically by Project 1's CI (`trigger-deploy` job dispatches to this repo). For a manual deploy:

```bash
# Via GitHub Actions workflow_dispatch (preferred):
gh workflow run deploy.yml -f image_tag=<COMMIT_SHA>

# Emergency direct kubectl:
kubectl set image deployment/api \
  api=<ACR_NAME>.azurecr.io/agentic-erp-api:<TAG>
kubectl set image deployment/frontend \
  frontend=<ACR_NAME>.azurecr.io/agentic-erp-frontend:<TAG>
kubectl rollout status deployment/api --timeout=120s
kubectl rollout status deployment/frontend --timeout=120s
```

### 8. Run smoke tests

```bash
SMOKE_BASE_URL=http://erp.131-189-252-158.nip.io ./scripts/smoke-test.sh
```

All 6 tests must pass before marking a deployment production-ready.

---

## CI/CD Architecture

```
Project 1 CI (push to master)         Project 2 Deploy (triggered)
──────────────────────────────         ────────────────────────────
backend-quality
frontend-quality
integration-tests
red-team
build-and-push-images
  ├── docker build + push → ACR
  └── trigger-deploy ─────────────►  repository_dispatch: "deploy"
                                           │
                                    deploy.yml
                                           ├── environment: production
                                           │   (manual approval gate)
                                           ├── kubectl apply -k k8s/base/
                                           ├── kubectl set image (api + frontend)
                                           └── smoke-test job (6 checks)
```

Image tags carry the short Git SHA from Project 1 (e.g., `ff046e2`). The deploy workflow trims whitespace from downloaded tags before passing them to `kubectl set image` to prevent `InvalidImageName` errors.

---

## Azure Resources

| Resource | SKU | Purpose | Est. Cost |
|----------|-----|---------|-----------|
| AKS cluster | Standard_B2s × 2 | Container orchestration | ~$60/mo |
| PostgreSQL Flexible | B1ms | ERP data + pgvector | ~$25/mo |
| Container Registry | Basic | Image storage | ~$5/mo |
| Redis Cache | Basic C0 | Semantic cache + HiTL decisions | ~$16/mo |
| App Insights + Log Analytics | PerGB2018 | Traces, metrics, alerts | ~$10/mo |
| **Total** | | | **~$116/mo** |

> **Note:** Cosmos DB Gremlin API (blueprint target for production KG) was unavailable in East US at deployment time. Neo4j 5.26 runs as an in-cluster Deployment (`k8s/base/neo4j.yaml`) with a 5 Gi PVC. See DEV-04 in `Project_Notes.md`.

---

## Kubernetes Manifests (`k8s/base/`)

| File | Purpose |
|------|---------|
| `api-deployment.yaml` | API pod (1 replica — see DEV-03); image: `ACR_PLACEHOLDER` |
| `api-service.yaml` | ClusterIP service, port 80 → container 8000 |
| `frontend-deployment.yaml` | Frontend pod (nginx:alpine); image: `ACR_PLACEHOLDER` |
| `frontend-service.yaml` | ClusterIP service, port 80 → container 80 |
| `configmap.yaml` | Non-secret runtime config (CORS origins, LLM model, thresholds) |
| `ingress.yaml` | NGINX Ingress: `/api/*` + `/ws/*` + `/docs` + `/health` → api; `/*` → frontend |
| `neo4j.yaml` | Neo4j 5.26 in-cluster: PVC (5 Gi), Deployment (768 Mi request / 1 Gi limit), ClusterIP |
| `neo4j-seed-job.yaml` | One-shot Job: seeds 14 suppliers, 9 components, 4 products, 3 DCs via cypher-shell |
| `kustomization.yaml` | Kustomize resource list for `kubectl apply -k` |

---

## Deployment Gates

A release to production requires **all** of:

- [ ] Project 1 CI pipeline green (lint + unit + integration + red-team)
- [ ] Docker images built and pushed to ACR
- [ ] `az deployment group validate` passes (Bicep templates)
- [ ] Manual approval via GitHub environment protection rule (`production`)
- [ ] Smoke test passes (6 representative checks)
- [ ] No P0/P1 issues in the last 24 hours

---

## Rollback

| Scenario | Command |
|----------|---------|
| Bad API deploy | `kubectl rollout undo deployment/api` |
| Bad frontend deploy | `kubectl rollout undo deployment/frontend` |
| Revert to specific image | `kubectl set image deployment/api api=<ACR>/agentic-erp-api:<old-sha>` |
| LLM regression (no redeploy) | Update `LLM_MODEL` in ConfigMap, restart pods |
| Database corruption | Azure Portal → PostgreSQL → Point-in-time restore (7-day retention) |

---

## Monitoring

- **Grafana dashboard**: `monitoring/dashboards/production.json` — import into a Grafana instance
- **Alerts**: P95 latency > 10 s, error rate > 5%, pod restarts > 3
- **OpenTelemetry**: traces forwarded to App Insights via `monitoring/otel-collector.yaml` DaemonSet
- **LangSmith**: agent trajectories, token usage, per-node latency

---

## Directory Structure

```
Agentic-ERP-Deploy/
├── .github/workflows/
│   ├── deploy.yml          # Deploy to AKS (repository_dispatch or workflow_dispatch)
│   └── infra.yml           # Provision/update Azure infra (manual, what-if mode)
├── infra/
│   ├── main.bicep          # Root Bicep orchestrator
│   ├── modules/
│   │   ├── aks.bicep       # AKS cluster (Standard_B2s × 2)
│   │   ├── postgres.bicep  # PostgreSQL Flexible (B1ms)
│   │   ├── cosmosdb.bicep  # Cosmos DB Gremlin (provisioned but unused — see DEV-04)
│   │   ├── redis.bicep     # Redis Cache Basic C0
│   │   ├── acr.bicep       # Attaches AKS role to existing ACR (does not create)
│   │   ├── monitoring.bicep# App Insights + Log Analytics
│   │   └── search.bicep    # Azure AI Search (free tier)
│   └── parameters/
│       ├── dev.bicepparam
│       └── prod.bicepparam
├── k8s/
│   ├── base/               # Base Kubernetes manifests (applied with kubectl apply -k)
│   └── overlays/           # Kustomize overlays (staging / production)
├── monitoring/
│   ├── alerts.bicep        # Azure Monitor alert rules
│   ├── dashboards/         # Grafana dashboard JSON
│   └── otel-collector.yaml # OTel Collector DaemonSet → App Insights
├── scripts/
│   ├── provision.sh        # Bicep deployment with what-if preview
│   └── smoke-test.sh       # Post-deploy validation (6 tests)
├── azure.yaml              # azd project definition
├── .env.example            # All required environment variables with descriptions
├── Developer_Log.md        # Chronological error/fix tracker — append all incidents here
└── Project_Notes.md        # Architectural decisions and deviations from the blueprint
```

---

## Known Deviations from Blueprint

| ID | Area | Actual vs. Blueprint |
|----|------|---------------------|
| DEV-01 | Domain | `erp.131-189-252-158.nip.io` (nip.io wildcard DNS), HTTP only — no custom domain or TLS |
| DEV-02 | Pod identity | No Workload Identity; credentials supplied via `app-secrets` env vars |
| DEV-03 | API replicas | 1 replica (OOMKill on 2× Standard_B2s with torch loaded) |
| DEV-04 | Knowledge graph | Neo4j 5.26 in-cluster instead of Cosmos DB Gremlin (region capacity failure) |
| DEV-05 | WebSocket headers | `configuration-snippet` removed; `proxy-http-version: "1.1"` is sufficient |
| DEV-06 | Frontend env vars | `VITE_WS_BASE_URL` and `VITE_API_BASE_URL` baked in at Docker build time |
| DEV-07 | Kustomize base | `kustomization.yaml` added (was missing from initial scaffold) |

Full details with rationale and remediation debt in [`Project_Notes.md`](Project_Notes.md).

---

## Related

- [Project 1: Agentic-ERP-SupplyChain-Copilot](https://github.com/Gabin-Maxime/Agentic-ERP-SupplyChain-Copilot) — application code, CI, Docker Compose
- [Developer Log](Developer_Log.md) — chronological error/fix tracker
- [Project Notes](Project_Notes.md) — architectural decisions and deviations
