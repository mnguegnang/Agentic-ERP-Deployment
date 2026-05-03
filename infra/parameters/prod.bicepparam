// infra/parameters/prod.bicepparam
// Production environment parameters.
// Blueprint budget: ~$116/mo (within $170 ceiling).
using '../main.bicep'

param environment = 'production'
param prefix = 'erpprod'
param aksNodeCount = 2       // 2x Standard_B2s ~$60/mo
// pgAdminPassword: injected at deploy time from GitHub secret PG_PASSWORD
// redisKey: injected at deploy time from GitHub secret REDIS_KEY
