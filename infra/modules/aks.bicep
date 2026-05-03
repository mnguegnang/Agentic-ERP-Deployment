// infra/modules/aks.bicep
// AKS cluster — System node pool: Standard_B2s x 2 nodes (~$60/mo).
// Blueprint Section 7.4.
targetScope = 'resourceGroup'

@description('AKS cluster name.')
param clusterName string

@description('Azure region.')
param location string

@description('Number of system nodes.')
@minValue(1)
@maxValue(10)
param nodeCount int = 2

@description('Resource ID of the ACR for role assignment.')
param acrId string

@description('Resource tags.')
param tags object = {}

// ─── AKS Cluster ───────────────────────────────────────────────────────────
resource aks 'Microsoft.ContainerService/managedClusters@2024-06-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    kubernetesVersion: '1.31'
    enableRBAC: true

    agentPoolProfiles: [
      {
        name: 'system'
        count: nodeCount
        vmSize: 'Standard_B2s'           // 2 vCPU, 4 GB RAM — budget-optimised
        osType: 'Linux'
        mode: 'System'
        enableAutoScaling: false          // fixed for budget predictability
        osDiskSizeGB: 50
        type: 'VirtualMachineScaleSets'
        maxPods: 30
      }
    ]

    networkProfile: {
      networkPlugin: 'kubenet'
      loadBalancerSku: 'standard'
    }

    addonProfiles: {
      omsagent: {
        enabled: true                     // container insights
      }
    }

    oidcIssuerProfile: {
      enabled: true                       // enables Workload Identity
    }

    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

// ─── ACR Pull Role Assignment ───────────────────────────────────────────────
// Assign AcrPull to the AKS kubelet identity so nodes can pull images.
var acrPullRoleDefId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'  // AcrPull built-in
)

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, acrId, acrPullRoleDefId)
  scope: resourceGroup()
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: acrPullRoleDefId
    principalType: 'ServicePrincipal'
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────
output clusterName string = aks.name
output clusterId string = aks.id
output apiServerUrl string = aks.properties.fqdn
output kubeletPrincipalId string = aks.properties.identityProfile.kubeletidentity.objectId
