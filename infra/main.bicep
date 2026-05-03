// infra/main.bicep
// Root Bicep template — orchestrates all Azure resource modules.
// Deployed via: az deployment group create / azd up / infra.yml workflow.
//
// Budget target: ~$116/mo (within $170 ceiling).
// See blueprint Section 7.4 for SKU rationale.

targetScope = 'resourceGroup'

// ─── Parameters ────────────────────────────────────────────────────────────
@description('Deployment environment tag.')
@allowed(['dev', 'staging', 'production'])
param environment string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name prefix for all resources (max 10 chars, alphanumeric).')
@maxLength(10)
param prefix string = 'erpcopilot'

@description('ACR name (must match Project 1 secret ACR_NAME).')
param acrName string

@description('AKS node count per system pool.')
@minValue(1)
@maxValue(10)
param aksNodeCount int = 2

@description('PostgreSQL admin password. Injected from Key Vault or GitHub secret.')
@secure()
param pgAdminPassword string

@description('Redis auth key. Injected from Key Vault or GitHub secret.')
@secure()
param redisKey string

// ─── Variables ─────────────────────────────────────────────────────────────
var suffix = uniqueString(resourceGroup().id, environment)
var tags = {
  project: 'agentic-erp-copilot'
  environment: environment
  managedBy: 'bicep'
}

// ─── Modules ───────────────────────────────────────────────────────────────

// Container Registry (consumed by AKS, not created here — already in Project 1)
// We reference the existing ACR by name to attach AKS role assignment.
module acr 'modules/acr.bicep' = {
  name: 'acr-module'
  params: {
    acrName: acrName
    location: location
    tags: tags
  }
}

// AKS Cluster
module aks 'modules/aks.bicep' = {
  name: 'aks-module'
  params: {
    clusterName: '${prefix}-aks-${environment}'
    location: location
    nodeCount: aksNodeCount
    acrId: acr.outputs.acrId
    tags: tags
  }
}

// PostgreSQL Flexible Server
module postgres 'modules/postgres.bicep' = {
  name: 'postgres-module'
  params: {
    serverName: '${prefix}-pg-${suffix}'
    location: location
    adminPassword: pgAdminPassword
    tags: tags
  }
}

// Cosmos DB (Gremlin API — free tier)
module cosmosdb 'modules/cosmosdb.bicep' = {
  name: 'cosmosdb-module'
  params: {
    accountName: '${prefix}-cosmos-${suffix}'
    location: location
    tags: tags
  }
}

// Redis Cache (Basic C0)
module redis 'modules/redis.bicep' = {
  name: 'redis-module'
  params: {
    cacheName: '${prefix}-redis-${suffix}'
    location: location
    tags: tags
  }
}

// App Insights + Log Analytics Workspace
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-module'
  params: {
    workspaceName: '${prefix}-law-${suffix}'
    appInsightsName: '${prefix}-ai-${suffix}'
    location: location
    tags: tags
  }
}

// Azure AI Search (free tier)
module search 'modules/search.bicep' = {
  name: 'search-module'
  params: {
    searchName: '${prefix}-search-${suffix}'
    location: location
    tags: tags
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output aksName string = aks.outputs.clusterName
output aksApiServerUrl string = aks.outputs.apiServerUrl
output postgresHost string = postgres.outputs.fqdn
output redisHost string = redis.outputs.hostName
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId
output searchEndpoint string = search.outputs.endpoint
output cosmosEndpoint string = cosmosdb.outputs.endpoint
