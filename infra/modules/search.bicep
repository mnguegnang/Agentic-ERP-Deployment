// infra/modules/search.bicep
// Azure AI Search — Free tier (50 MB, 3 indexes, $0/mo).
// Used for supplementary full-text search on ERP entities.
// Blueprint Section 7.4.
targetScope = 'resourceGroup'

@description('Azure AI Search service name (must be globally unique, 2-60 chars, lowercase).')
param searchName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

// ─── Azure AI Search ────────────────────────────────────────────────────────
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchName
  location: location
  tags: tags
  sku: {
    name: 'free'               // Free tier: 50 MB, 3 indexes — $0/mo
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}           // API key auth for simplicity in dev/staging
    }
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output searchId string = searchService.id
output endpoint string = 'https://${searchName}.search.windows.net'
output adminKeyPrimary string = searchService.listAdminKeys().primaryKey
