# Agentic-ERP-Deploy — README

> **Project 2 of 2** | Stage 7 — Production Deployment  
> Companion to: [`Agentic-ERP-SupplyChain-Copilot`](https://github.com/YOUR_ORG/Agentic-ERP-SupplyChain-Copilot) (Project 1)  
> Blueprint: `Agentic_Decision_Intelligence_Implementation_Blueprint.md` — Stage 7

This repository owns all infrastructure-as-code, deployment workflows, Kubernetes manifests, and production monitoring for the Agentic ERP Supply Chain Copilot system. It **never builds application code** — it consumes container images built and pushed to Azure Container Registry by Project 1's CI pipeline.

---

## Prerequisites

### Gate: Dev-Complete (M8)

**Do not start Project 2 until Project 1's M8 gate has passed.** This requires:

- All 7 solver unit tests green  
- Full agent eval: intent accuracy ≥ 90%, tool precision ≥ 95%  
- Red-team: 0% injection success  
- Docker Compose boots all 5 services  
- Video demo recorded

### Tools required

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
git clone https://github.com/YOUR_ORG/Agentic-ERP-Deploy.git
cd Agentic-ERP-Deploy
cp .env.example .env
# Edit .env with your Azure credentials and resource names
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
# Runs az deployment group create with Bicep templates
# Prompts for what-if preview before applying
# Automatically fetches AKS credentials on success
```

Estimated provisioning time: ~8 minutes.  
Estimated monthly cost: ~$116 (within $170 budget — see blueprint Section 7.4).

### 4. Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.loadBalancerIP=""
```

### 5. Apply TLS certificate (cert-manager recommended)

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true
# Then create a ClusterIssuer for Let's Encrypt and patch ingress.yaml
```

### 6. Deploy the application

Deployment is normally triggered automatically by Project 1's CI (`trigger-deploy` job). For manual deploy:

```bash
# Via GitHub Actions workflow_dispatch:
gh workflow run deploy.yml -f image_tag=<COMMIT_SHA>

# Or directly with kubectl (emergency use only):
kubectl set image deployment/api api=<ACR>.azurecr.io/api:<TAG> --namespace default
kubectl set image deployment/frontend frontend=<ACR>.azurecr.io/frontend:<TAG> --namespace default
kubectl rollout status deployment/api --timeout=120s
kubectl rollout status deployment/frontend --timeout=120s
```

### 7. Run smoke tests

```bash
SMOKE_BASE_URL=https://your-domain ./scripts/smoke-test.sh
```

All 6 tests must pass before marking a deployment production-ready.

---

## Architecture

```
Project 1 CI (auto)                  Project 2 Deploy (triggered)
───────────────────                  ─────────────────────────────
push to main
  ├─ lint + test
  ├─ red-team
  ├─ build + push images → ACR
  └─ trigger-deploy ─────────────→   repository_dispatch event
       (GitHub API)                       │
                                          ├─ deploy job
                                          │   └─ environment: production
                                          │      (manual approval gate)
                                          └─ smoke-test job
```

### Azure Resources

| Resource | SKU | Purpose | Est. Cost |
|----------|-----|---------|-----------|
| AKS cluster | Standard_B2s × 2 | Container orchestration | ~$60/mo |
| PostgreSQL Flexible | B1ms | ERP data + pgvector | ~$25/mo |
| Cosmos DB (Gremlin) | Free tier | Production KG | $0 |
| Azure AI Search | Free tier | Full-text search | $0 |
| Container Registry | Basic | Image storage | ~$5/mo |
| Redis Cache | Basic C0 | Semantic cache + HiTL | ~$16/mo |
| Monitoring | PerGB2018 LAW | Traces, metrics, alerts | ~$10/mo |
| **Total** | | | **~$116/mo** |

---

## Deployment Gates

A release to production requires **all** of:

- [ ] Project 1 CI pipeline green (lint + unit + integration + red-team)
- [ ] Docker images built and pushed to ACR
- [ ] `az deployment group validate` passes (Bicep templates)
- [ ] Smoke test passes on staging (6 representative queries)
- [ ] No P0/P1 issues in the last 24 hours
- [ ] Manual approval via GitHub environment protection rule

---

## Rollback

| Scenario | Command |
|----------|---------|
| Bad deploy (error spike) | `kubectl rollout undo deployment/api` |
| Bad frontend deploy | `kubectl rollout undo deployment/frontend` |
| Revert to specific image | `kubectl set image deployment/api api=<ACR>/<image>:<old-tag>` |
| SLM regression (no redeploy) | Set `MODEL_BACKEND=openai_api` in ConfigMap, restart pods |
| Database corruption | Azure Portal → PostgreSQL → Point-in-time restore (7-day retention) |

---

## Monitoring

- **Grafana dashboard**: `monitoring/dashboards/production.json` — import into Grafana
- **Alerts**: P95 latency > 10s, error rate > 5%, pod restarts > 3
- **OpenTelemetry**: traces forwarded to App Insights via `monitoring/otel-collector.yaml`
- **LangSmith**: agent trajectories, token usage, per-node latency

---

## Directory Structure

```
Agentic-ERP-Deploy/
├── .github/workflows/
│   ├── deploy.yml          # Deploy to AKS (repository_dispatch or manual)
│   └── infra.yml           # Provision/update Azure infra (manual)
├── infra/
│   ├── main.bicep          # Root Bicep orchestrator
│   ├── modules/
│   │   ├── aks.bicep       # AKS cluster (B2s × 2)
│   │   ├── postgres.bicep  # PostgreSQL Flexible (B1ms)
│   │   ├── cosmosdb.bicep  # Cosmos DB Gremlin (free)
│   │   ├── redis.bicep     # Redis Cache Basic C0
│   │   ├── acr.bicep       # Container Registry Basic
│   │   ├── monitoring.bicep# App Insights + Log Analytics
│   │   └── search.bicep    # Azure AI Search (free)
│   └── parameters/
│       ├── dev.bicepparam
│       └── prod.bicepparam
├── k8s/
│   ├── base/               # Base Kubernetes manifests
│   └── overlays/           # Kustomize overlays (staging / production)
├── monitoring/
│   ├── alerts.bicep        # Azure Monitor alert rules
│   ├── dashboards/         # Grafana dashboard JSON
│   └── otel-collector.yaml # OTel Collector DaemonSet
├── scripts/
│   ├── provision.sh        # azd up wrapper with what-if preview
│   └── smoke-test.sh       # Post-deploy validation (6 tests)
├── azure.yaml              # azd project definition
├── .env.example            # Required environment variables
├── .gitignore
├── README.md               # This file
├── Developer_Log.md        # Chronological error/fix tracker
└── Project_Notes.md        # Architectural decisions and deviations
```

---

## Related

- [Project 1: Agentic-ERP-SupplyChain-Copilot](https://github.com/YOUR_ORG/Agentic-ERP-SupplyChain-Copilot) — application code, CI, Docker Compose
- Blueprint: `Agentic_Decision_Intelligence_Implementation_Blueprint.md`
