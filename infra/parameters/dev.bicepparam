// infra/parameters/dev.bicepparam
// Development environment parameters.
// Smallest SKUs — cost optimised for local developer testing with cloud services.
using '../main.bicep'

param environment = 'dev'
param prefix = 'erpdev'
param aksNodeCount = 1       // single node saves ~$30/mo in dev
// pgAdminPassword: injected at deploy time from GitHub secret PG_PASSWORD
// redisKey: injected at deploy time from GitHub secret REDIS_KEY
