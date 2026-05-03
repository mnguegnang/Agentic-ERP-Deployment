// infra/modules/acr.bicep
// Azure Container Registry — Basic SKU (~$5/mo).
// Project 1 CI pushes images here; AKS pulls from here.
// Blueprint Section 7.4.
targetScope = 'resourceGroup'

@description('ACR name. Must match Project 1 CI secret ACR_NAME.')
param acrName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

// ─── Container Registry ────────────────────────────────────────────────────
// NOTE: ACR may already exist (created by Project 1 setup).
// This module references it via a conditional create-or-reference pattern.
// If the ACR does not exist, it will be created here.
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'              // ~$5/mo, sufficient for this project
  }
  properties: {
    adminUserEnabled: false    // use managed identity / service principal auth
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
    policies: {
      retentionPolicy: {
        status: 'enabled'
        days: 7                // retain images for 7 days
      }
    }
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output acrId string = acr.id
output loginServer string = acr.properties.loginServer
