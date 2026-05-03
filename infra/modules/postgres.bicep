// infra/modules/postgres.bicep
// PostgreSQL Flexible Server — B1ms (1 vCPU, 2 GB) ~$25/mo.
// Blueprint Section 7.4.
targetScope = 'resourceGroup'

@description('PostgreSQL server name (must be globally unique).')
param serverName string

@description('Azure region.')
param location string

@description('Administrator password.')
@secure()
param adminPassword string

@description('Administrator login username.')
param adminLogin string = 'aw_admin'

@description('PostgreSQL version.')
param postgresVersion string = '16'

@description('Resource tags.')
param tags object = {}

// ─── PostgreSQL Flexible Server ────────────────────────────────────────────
resource pgServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'      // 1 vCPU, 2 GB — budget optimised
    tier: 'Burstable'
  }
  properties: {
    version: postgresVersion
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'          // no HA for dev/staging budget
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
  }
}

// ─── Database: adventureworks ───────────────────────────────────────────────
resource adventureworksDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pgServer
  name: 'adventureworks'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// ─── Firewall: allow Azure services ────────────────────────────────────────
// AKS pods egress via the load-balancer public IP.
// Fine-grained VNet integration should be set up for production.
resource fwAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pgServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'    // 0.0.0.0 / 0.0.0.0 = allow all Azure services
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output serverId string = pgServer.id
output fqdn string = pgServer.properties.fullyQualifiedDomainName
output databaseName string = adventureworksDb.name
output adminLogin string = adminLogin
