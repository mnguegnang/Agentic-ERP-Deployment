// infra/modules/redis.bicep
// Azure Cache for Redis — Basic C0 (256 MB) ~$16/mo.
// Blueprint Section 7.4.
targetScope = 'resourceGroup'

@description('Redis cache name (must be globally unique).')
param cacheName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

// ─── Redis Cache ────────────────────────────────────────────────────────────
resource redisCache 'Microsoft.Cache/Redis@2024-04-01-preview' = {
  name: cacheName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0              // C0: 256 MB — smallest SKU, fits budget
    }
    enableNonSslPort: false    // enforce TLS
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'   // evict least-recently-used keys
    }
    publicNetworkAccess: 'Enabled'
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output cacheId string = redisCache.id
output hostName string = redisCache.properties.hostName
output sslPort int = redisCache.properties.sslPort
output redisUrl string = 'rediss://${redisCache.properties.hostName}:${redisCache.properties.sslPort}'
