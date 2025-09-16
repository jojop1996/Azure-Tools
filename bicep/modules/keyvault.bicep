@description('Specifies the name of the key vault.')
param keyVaultName string = 'kv'

@description('Specifies the Azure location where the key vault should be created.')
param location string = resourceGroup().location

@description('Specifies whether Azure Virtual Machines are permitted to retrieve certificates stored as secrets from the key vault.')
param enabledForDeployment bool = true

@description('Specifies whether Azure Disk Encryption is permitted to retrieve secrets from the vault and unwrap keys.')
param enabledForDiskEncryption bool = false

@description('Specifies whether Azure Resource Manager is permitted to retrieve secrets from the key vault.')
param enabledForTemplateDeployment bool = true

@description('Specifies the Azure Active Directory tenant ID that should be used for authenticating requests to the key vault.')
param tenantId string = subscription().tenantId

@description('Specifies whether the key vault is a standard vault or a premium vault.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Network access configuration')
@allowed([
  'Allow'
  'Deny'
])
param networkDefaultAction string = 'Allow'

@description('A unique token used for resource name generation.')
@minLength(3)
param resourceToken string = toLower(uniqueString(subscription().id, location))

@description('Specifies the object ID of the user or service principal that will have access to the key vault.')
param objectId string = ''

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${keyVaultName}-${resourceToken}'
  location: location
  properties: {
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    tenantId: tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    sku: {
      name: skuName
      family: 'A'
    }
    networkAcls: {
      defaultAction: networkDefaultAction
      bypass: 'AzureServices'
    }
    accessPolicies: objectId != '' ? [
      {
        tenantId: tenantId
        objectId: objectId
        permissions: {
          keys: [
            'get'
            'list'
            'create'
            'delete'
            'backup'
            'restore'
            'recover'
            'purge'
          ]
          secrets: [
            'get'
            'list'
            'set'
            'delete'
            'backup'
            'restore'
            'recover'
            'purge'
          ]
          certificates: [
            'get'
            'list'
            'delete'
            'create'
            'import'
            'update'
            'managecontacts'
            'getissuers'
            'listissuers'
            'setissuers'
            'deleteissuers'
            'manageissuers'
            'recover'
            'purge'
          ]
        }
      }
    ] : []
  }
}
