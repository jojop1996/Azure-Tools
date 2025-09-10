@description('Primary region for all Azure resources.')
@minLength(1)
param location string = resourceGroup().location

@description('Language runtime used by the function app.')
@allowed(['dotnet-isolated','python','java', 'node', 'powerShell'])
param appRuntime string

@description('Target language version used by the function app.')
param appRuntimeVersion string

@description('The maximum scale-out instance count limit for the app.')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 40

@description('The memory size of instances used by the app.')
@allowed([2048,4096])
param instanceMemoryMB int = 2048

@description('A unique token used for resource name generation.')
@minLength(3)
param resourceToken string = toLower(uniqueString(subscription().id, location))

@description('The name for your deployed function app.')
param appName string

@description('The type of hosting plan to use for the function app.')
@allowed(['FlexConsumption', 'Consumption', 'Premium'])
param planType string

//********************************************
// Variables
//********************************************

// Combined naming token for consistent resource naming.
var appNameToken = '${appName}-${resourceToken}'

// Generates a unique container name for deployments.
// Restrained to 63 characters to stay within Azure's naming length limits.
var deploymentStorageContainerName = 'app-package-${take(appNameToken, 39)}'

// Sanitize and constrain storage account name to Azure requirements:
// - lowercase
// - remove hyphens
// - max length 24 characters
// - prefix with 'sta' to keep a recognizable prefix to meet the 3 character minimum requirement
var storageAccountNameCleaned = replace(toLower(appNameToken), '-', '')
var storageAccountName = 'sta${take(storageAccountNameCleaned, 21)}'

// Key access to the storage account is disabled by default.
var storageAccountAllowSharedKeyAccess = false

// Define the IDs of the roles we need to assign to our managed identities.
var storageBlobDataOwnerRoleId  = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageQueueDataContributorId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var monitoringMetricsPublisherId = '3913510d-42f4-4e42-8a64-420c390055eb'

//********************************************
// Azure resources required by function app.
//********************************************

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${appNameToken}'
  location: location
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  })
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${appNameToken}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    DisableLocalAuth: true
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: storageAccountAllowSharedKeyAccess
    dnsEndpointType: 'Standard'
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }
  resource blobServices 'blobServices' = {
    name: 'default'
    properties: {
      deleteRetentionPolicy: {
        enabled: false
        allowPermanentDelete: false
      }
    }
    resource deploymentContainer 'containers' = {
      name: deploymentStorageContainerName
      properties: {
        publicAccess: 'None'
        defaultEncryptionScope: '$account-encryption-key'
        denyEncryptionScopeOverride: false
      }
    }
  }
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uai-data-owner-${appNameToken}'
  location: location
}

resource roleAssignmentBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, storage.id, userAssignedIdentity.id, 'Storage Blob Data Owner')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, storage.id, userAssignedIdentity.id, 'Storage Blob Data Contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentQueueStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, storage.id, userAssignedIdentity.id, 'Storage Queue Data Contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentTableStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, storage.id, userAssignedIdentity.id, 'Storage Table Data Contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentAppInsights 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, applicationInsights.id, userAssignedIdentity.id, 'Monitoring Metrics Publisher')
  scope: applicationInsights
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

//********************************************
// Function app and plan definitions
//********************************************

// Define SKU configuration based on plan type.
var planConfig = planType == 'FlexConsumption' ? {
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true
  }
} : planType == 'Consumption' ? {
  kind: 'functionapp'
  sku: {
    tier: 'Dynamic'
    name: 'Y1'
  }
  properties: {
    reserved: true
  }
} : planType == 'Premium' ? {
  kind: 'functionapp'
  sku: {
    tier: 'ElasticPremium'
    name: 'EP1'
  }
  properties: {
    reserved: true
  }
} : {}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-${appNameToken}'
  location: location
  kind: planConfig.kind
  sku: planConfig.sku
  properties: planConfig.properties
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'func-${appNameToken}'
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}':{}
      }
    }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
    }
    // FlexConsumption requires functionAppConfig.
    functionAppConfig: planType == 'FlexConsumption' ? {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentStorageContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: userAssignedIdentity.id
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: { 
        name: appRuntime
        version: appRuntimeVersion
      }
    } : null
  }
  resource configAppSettings 'config' = {
    name: 'appsettings'
    properties: union({
        AzureWebJobsStorage__accountName: storage.name
        AzureWebJobsStorage__credential : 'managedidentity'
        AzureWebJobsStorage__clientId: userAssignedIdentity.properties.clientId
        APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
        APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${userAssignedIdentity.properties.clientId};Authorization=AAD'
        FUNCTIONS_EXTENSION_VERSION: '~4'
      }, planType != 'FlexConsumption' ? {
        FUNCTIONS_WORKER_RUNTIME: appRuntime
        WEBSITE_PYTHON_VERSION: appRuntimeVersion
      } : {})
  }
}
