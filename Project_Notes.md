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

None yet. All structures match blueprint Section 1.1.2 and Stage 7 exactly.

---

<!-- Append new deviation entries below as they occur -->
