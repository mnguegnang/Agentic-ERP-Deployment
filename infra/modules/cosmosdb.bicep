// infra/modules/cosmosdb.bicep
// Azure Cosmos DB (Gremlin API) — Free tier ($0/mo up to 1000 RU/s, 25 GB).
// Used as the production graph store replacing the local Neo4j container.
// Blueprint Section 7.4.
targetScope = 'resourceGroup'

@description('Cosmos DB account name (must be globally unique, 3-44 chars, lowercase).')
param accountName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

// ─── Cosmos DB Account (Gremlin API) ───────────────────────────────────────
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'     // required for Gremlin
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: true        // $0 up to 1000 RU/s + 25 GB
    capabilities: [
      { name: 'EnableGremlin' }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    publicNetworkAccess: 'Enabled'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 1440    // daily
        backupRetentionIntervalInHours: 168  // 7 days
      }
    }
    disableLocalAuth: false
  }
}

// ─── Gremlin Database ───────────────────────────────────────────────────────
resource gremlinDb 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: 'supply-chain-kg'
  properties: {
    resource: {
      id: 'supply-chain-kg'
    }
    options: {
      throughput: 400            // minimum RU/s, covered by free tier
    }
  }
}

// ─── Gremlin Graph: supply_network ─────────────────────────────────────────
resource gremlinGraph 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs@2024-05-15' = {
  parent: gremlinDb
  name: 'supply_network'
  properties: {
    resource: {
      id: 'supply_network'
      partitionKey: {
        paths: [ '/partitionKey' ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [ { path: '/*' } ]
        excludedPaths: [ { path: '/"_etag"/?' } ]
      }
    }
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output accountId string = cosmosAccount.id
output endpoint string = cosmosAccount.properties.documentEndpoint
output gremlinEndpoint string = 'wss://${accountName}.gremlin.cosmos.azure.com:443/'
output primaryKey string = cosmosAccount.listKeys().primaryMasterKey
