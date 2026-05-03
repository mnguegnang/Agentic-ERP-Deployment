#!/usr/bin/env bash
# scripts/provision.sh
# Wrapper around `azd up` for Agentic-ERP-Deploy.
# Provisions Azure infrastructure (Bicep) + applies Kubernetes manifests.
#
# Usage:
#   ./scripts/provision.sh [staging|production]
#
# Prerequisites:
#   - az CLI authenticated (az login)
#   - azd CLI installed (brew install azure-developer-cli)
#   - AZURE_CREDENTIALS environment variable set (or az login active)
#   - .env file present with required secrets (see .env.example)
#
# Blueprint Section 7.3.
set -euo pipefail

ENVIRONMENT="${1:-staging}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Validate environment ─────────────────────────────────────────────────────
[[ "$ENVIRONMENT" =~ ^(staging|production)$ ]] \
  || error "Invalid environment '${ENVIRONMENT}'. Use: staging | production"

info "Target environment: ${ENVIRONMENT}"

# ─── Load environment variables ───────────────────────────────────────────────
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "$ENV_FILE" ]]; then
  info "Loading secrets from .env"
  set -a; source "$ENV_FILE"; set +a
else
  warn ".env not found. Assuming secrets are already in the shell environment."
fi

# ─── Validate required secrets ────────────────────────────────────────────────
REQUIRED_VARS=(AZURE_CREDENTIALS RG_NAME ACR_NAME PG_PASSWORD)
for var in "${REQUIRED_VARS[@]}"; do
  [[ -n "${!var:-}" ]] || error "Required environment variable '${var}' is not set."
done

# ─── Login to Azure ───────────────────────────────────────────────────────────
info "Logging in to Azure..."
echo "$AZURE_CREDENTIALS" | az login --service-principal \
  --username "$(echo "$AZURE_CREDENTIALS" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["clientId"])')" \
  --password "$(echo "$AZURE_CREDENTIALS" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["clientSecret"])')" \
  --tenant   "$(echo "$AZURE_CREDENTIALS" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["tenantId"])')" \
  --output none

# ─── Validate Bicep templates ─────────────────────────────────────────────────
info "Validating Bicep templates for environment: ${ENVIRONMENT}..."
az deployment group validate \
  --resource-group "$RG_NAME" \
  --template-file "${PROJECT_ROOT}/infra/main.bicep" \
  --parameters "${PROJECT_ROOT}/infra/parameters/${ENVIRONMENT}.bicepparam" \
  --parameters acrName="$ACR_NAME" \
  --parameters pgAdminPassword="$PG_PASSWORD" \
  --output none
info "Bicep validation passed."

# ─── What-if preview ─────────────────────────────────────────────────────────
info "Running what-if analysis..."
az deployment group what-if \
  --resource-group "$RG_NAME" \
  --template-file "${PROJECT_ROOT}/infra/main.bicep" \
  --parameters "${PROJECT_ROOT}/infra/parameters/${ENVIRONMENT}.bicepparam" \
  --parameters acrName="$ACR_NAME" \
  --parameters pgAdminPassword="$PG_PASSWORD"

read -rp "Proceed with deployment? (y/N): " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { info "Deployment cancelled."; exit 0; }

# ─── Deploy Bicep ─────────────────────────────────────────────────────────────
info "Deploying infrastructure to ${ENVIRONMENT}..."
az deployment group create \
  --resource-group "$RG_NAME" \
  --template-file "${PROJECT_ROOT}/infra/main.bicep" \
  --parameters "${PROJECT_ROOT}/infra/parameters/${ENVIRONMENT}.bicepparam" \
  --parameters acrName="$ACR_NAME" \
  --parameters pgAdminPassword="$PG_PASSWORD" \
  --mode Incremental \
  --output json | tee "${PROJECT_ROOT}/infra/last-deploy-${ENVIRONMENT}.json"

AKS_NAME=$(jq -r '.properties.outputs.aksName.value' \
  "${PROJECT_ROOT}/infra/last-deploy-${ENVIRONMENT}.json")
info "AKS cluster: ${AKS_NAME}"

# ─── Get AKS credentials ─────────────────────────────────────────────────────
info "Fetching AKS credentials..."
az aks get-credentials \
  --resource-group "$RG_NAME" \
  --name "$AKS_NAME" \
  --overwrite-existing

# ─── Apply Kubernetes manifests (Kustomize) ───────────────────────────────────
info "Applying Kubernetes manifests for ${ENVIRONMENT}..."
kubectl apply -k "${PROJECT_ROOT}/k8s/overlays/${ENVIRONMENT}"

# ─── Apply OTel collector ─────────────────────────────────────────────────────
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${PROJECT_ROOT}/monitoring/otel-collector.yaml"

info "Provision complete. Run smoke tests with:"
info "  ./scripts/smoke-test.sh"
