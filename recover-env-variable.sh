#!/usr/bin/env bash
set -euo pipefail

# Source the static parts (RG_NAME, LOCATION, etc.)
source .env

# Recover dynamic / sensitive values from Azure on every run
export ACR_NAME=$(az acr list -g "$RG_NAME" --query "[0].name" -o tsv)
export AKS_NAME=$(az aks list -g "$RG_NAME" --query "[0].name" -o tsv)
export PG_NAME=$(az postgres flexible-server list -g "$RG_NAME" --query "[0].name" -o tsv)
export PG_HOST=$(az postgres flexible-server show -g "$RG_NAME" -n "$PG_NAME" --query fullyQualifiedDomainName -o tsv)
export REDIS_NAME=$(az redis list -g "$RG_NAME" --query "[0].name" -o tsv)
export REDIS_HOST=$(az redis show -g "$RG_NAME" -n "$REDIS_NAME" --query hostName -o tsv)
export REDIS_KEY=$(az redis list-keys -g "$RG_NAME" -n "$REDIS_NAME" --query primaryKey -o tsv)
export APP_ID=$(az ad app list --display-name "app-github-agentic-erp-deploy" --query "[0].appId" -o tsv)
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)
export PG_ADMIN=$(az postgres flexible-server show \
  --resource-group "$RG_NAME" \
  --name "$PG_NAME" \
  --query "administratorLogin" -o tsv)

echo "   Recovered:"
echo "   ACR_NAME    = $ACR_NAME"
echo "   AKS_NAME    = $AKS_NAME"
echo "   PG_NAME     = $PG_NAME"
echo "   PG_HOST     = $PG_HOST"
echo "   REDIS_NAME  = $REDIS_NAME"
echo "   REDIS_HOST  = $REDIS_HOST"
echo "   REDIS_KEY   = (length ${#REDIS_KEY})"
echo "   APP_ID      = $APP_ID"
echo "   PG_ADMIN    = $PG_ADMIN"