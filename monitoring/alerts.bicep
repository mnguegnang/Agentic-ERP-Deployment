// monitoring/alerts.bicep
// Azure Monitor alert rules for production.
// Blueprint Section 7.5: P95 latency > 10s, error rate > 5%, pod restarts > 3.
targetScope = 'resourceGroup'

@description('Application Insights resource ID.')
param appInsightsId string

@description('Log Analytics workspace ID.')
param workspaceId string

@description('Alert notification email.')
param alertEmail string

@description('Resource tags.')
param tags object = {}

// ─── Action Group (email notifications) ────────────────────────────────────
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'agentic-erp-alerts'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'erp-alerts'
    enabled: true
    emailReceivers: [
      {
        name: 'on-call'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ─── Alert: P95 request latency > 10 seconds ───────────────────────────────
resource latencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'api-p95-latency-high'
  location: 'global'
  tags: tags
  properties: {
    description: 'API P95 request duration exceeds 10 seconds. Blueprint threshold.'
    severity: 2
    enabled: true
    scopes: [appInsightsId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'p95-latency'
          metricName: 'requests/duration'
          metricNamespace: 'microsoft.insights/components'
          operator: 'GreaterThan'
          threshold: 10000       // milliseconds
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [{ actionGroupId: actionGroup.id }]
  }
}

// ─── Alert: Error rate > 5% (5-minute window) ──────────────────────────────
resource errorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'api-error-rate-high'
  location: 'global'
  tags: tags
  properties: {
    description: 'API server error rate exceeds 5%. Blueprint threshold.'
    severity: 1
    enabled: true
    scopes: [appInsightsId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'error-rate'
          metricName: 'requests/failed'
          metricNamespace: 'microsoft.insights/components'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [{ actionGroupId: actionGroup.id }]
  }
}

// ─── Alert: Container pod restarts > 3 (Log Analytics query) ───────────────
resource podRestartAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'pod-restarts-high'
  location: resourceGroup().location
  tags: tags
  properties: {
    description: 'Pod restart count exceeds 3 in 10 minutes. Blueprint threshold.'
    severity: 2
    enabled: true
    scopes: [workspaceId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    criteria: {
      allOf: [
        {
          query: '''
            KubePodInventory
            | where ContainerRestartCount > 3
            | summarize MaxRestarts = max(ContainerRestartCount) by Computer, PodName
            | where MaxRestarts > 3
          '''
          timeAggregation: 'Count'
          metricMeasureColumn: 'MaxRestarts'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output actionGroupId string = actionGroup.id
