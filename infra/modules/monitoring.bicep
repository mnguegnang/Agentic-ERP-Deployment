// infra/modules/monitoring.bicep
// Log Analytics Workspace + Application Insights.
// Receives OpenTelemetry traces from the AKS workloads.
// Blueprint Section 7.5.
targetScope = 'resourceGroup'

@description('Log Analytics workspace name.')
param workspaceName string

@description('Application Insights resource name.')
param appInsightsName string

@description('Azure region.')
param location string

@description('Log Analytics retention in days.')
@minValue(30)
@maxValue(730)
param retentionDays int = 30

@description('Resource tags.')
param tags object = {}

// ─── Log Analytics Workspace ────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'        // pay-per-use, no commitment tier
    }
    retentionInDays: retentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ─── Application Insights ───────────────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'     // workspace-based (modern mode)
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output workspaceId string = logAnalytics.id
output workspaceCustomerId string = logAnalytics.properties.customerId
output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output instrumentationKey string = appInsights.properties.InstrumentationKey
