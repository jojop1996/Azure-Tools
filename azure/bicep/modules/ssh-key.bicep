@description('The location for the SSH key resource.')
param location string = resourceGroup().location

@description('Name for the SSH public key resource.')
param sshKeyName string

@description('The SSH public key content.')
param sshPublicKey string

resource sshKey 'Microsoft.Compute/sshPublicKeys@2023-03-01' = {
  name: sshKeyName
  location: location
  properties: {
    publicKey: sshPublicKey
  }
}

output sshKeyResourceId string = sshKey.id
output sshPublicKey string = sshKey.properties.publicKey
