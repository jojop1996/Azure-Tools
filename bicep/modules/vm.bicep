@description('The name of your Virtual Machine or VM Scale Set.')
param vmName string

@description('Platform for the deployment.')
@allowed([
  'Linux'
  'Windows'
])
param platform string = 'Linux'

@description('Deployment type: single VM or scale set.')
@allowed([
  'vm'
  'vmss'
])
param deploymentType string = 'vm'

@description('Username for the Virtual Machine(s).')
param adminUsername string

@description('Type of authentication to use. SSH key for Linux, password for Windows.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = (platform == 'Linux' ? 'sshPublicKey' : 'password')

@description('SSH Key or password for the Virtual Machine(s).')
@secure()
param adminPasswordOrKey string

@description('Unique DNS Name for the Public IP used to access the VM(s).')
param dnsLabelPrefix string = toLower(take('${vmName}-${uniqueString(resourceGroup().id)}', 63))

@description('The Ubuntu version for the VM(s).')
@allowed([
  'Ubuntu-2004'
  'Ubuntu-2204'
])
param ubuntuOSVersion string = 'Ubuntu-2204'

@description('The Windows version for the VM(s).')
@allowed([
  '2019-Datacenter'
  '2022-Datacenter'
  '2019-Datacenter-Core'
  '2022-Datacenter-Core'
  '2019-Datacenter-Gen2'
  '2022-Datacenter-Gen2'
])
param windowsOSVersion string = '2022-Datacenter-Gen2'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The size of the VM(s)')
param vmSize string = 'Standard_D2s_v3'

@description('Number of VM instances (for scale set).')
@minValue(1)
@maxValue(100)
param instanceCount int = 1

@description('CPU percentage threshold to trigger scale-out (increase instance count).')
@minValue(1)
@maxValue(100)
param scaleOutThreshold int = 50

@description('CPU percentage threshold to trigger scale-in (decrease instance count).')
@minValue(1)
@maxValue(100)
param scaleInThreshold int = 30

@description('Upgrade policy mode for VMSS (Manual, Automatic, Rolling).')
@allowed([
  'Manual'
  'Automatic'
  'Rolling'
])
param upgradePolicyMode string = 'Manual'

@description('Allow inbound admin access (RDP/SSH) only from this source. Use CIDR or IP. Default is open (not recommended for production).')
param allowedAdminSourceAddress string = '*'

@description('Enable boot diagnostics on VM/VMSS for troubleshooting.')
param enableBootDiagnostics bool = true

@description('Enable system-assigned managed identity on VM/VMSS.')
param enableSystemAssignedIdentity bool = false

@description('Enable accelerated networking on NICs when supported by VM size.')
param enableAcceleratedNetworking bool = false

@description('Tags applied to all resources created by this module.')
param tags object = {}

@description('Name of the VNET')
param virtualNetworkName string = 'vNet'

@description('Name of the subnet in the virtual network')
param subnetName string = 'Subnet'

@description('Name of the Network Security Group')
param networkSecurityGroupName string = 'SecGroupNet'

@description('Security Type of the Virtual Machine(s).')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'TrustedLaunch'

var imageReference = {
  Linux: {
    'Ubuntu-2004': {
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-focal'
      sku: '20_04-lts-gen2'
      version: 'latest'
    }
    'Ubuntu-2204': {
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-jammy'
      sku: '22_04-lts-gen2'
      version: 'latest'
    }
  }
  Windows: {
    '2019-Datacenter': {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2019-datacenter'
      version: 'latest'
    }
    '2022-Datacenter': {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter'
      version: 'latest'
    }
    '2019-Datacenter-Core': {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2019-datacenter-core'
      version: 'latest'
    }
    '2022-Datacenter-Core': {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-core'
      version: 'latest'
    }
    '2019-Datacenter-Gen2': {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2019-datacenter-g2'
      version: 'latest'
    }
    '2022-Datacenter-Gen2': {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-g2'
      version: 'latest'
    }
  }
}

var publicIPAddressName = '${vmName}PublicIP'
var networkInterfaceName = '${vmName}NetInt'
var osDiskType = 'Standard_LRS'
var subnetAddressPrefix = '10.1.0.0/24'
var addressPrefix = '10.1.0.0/16'

var linuxConfiguration = {
  disablePasswordAuthentication: (authenticationType == 'sshPublicKey')
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
}

var windowsConfiguration = {
  enableAutomaticUpdates: true
  provisionVMAgent: true
}

var securityProfileJson = {
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
  securityType: securityType
}

var extensionName = 'GuestAttestation'
var extensionPublisher = 'Microsoft.Azure.Security.LinuxAttestation'
var extensionVersion = '1.0'
var maaTenantName = 'GuestAttestation'
var maaEndpoint = substring('emptystring', 0, 0)

var lbName = '${vmName}LB'
var bePoolName = '${vmName}BackendPool'
var natPoolName = '${vmName}NatPool'
var natStartPort = 50000
var natEndPort = 50119
var natBackendPort = platform == 'Linux' ? 22 : 3389
// Use a different port for the load balancing rule to avoid conflict with inbound NAT pool backend port
var lbRulePort = natBackendPort + 1

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: networkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        // Allow Azure Load Balancer health probe traffic to backend port used by probe
        name: 'Allow-AzureLB-Probe'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: string(natBackendPort)
        }
      }
      {
        name: (platform == 'Linux' ? 'SSH' : 'RDP')
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedAdminSourceAddress
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: (platform == 'Linux' ? '22' : '3389')
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          addressPrefix: subnetAddressPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIPAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
    idleTimeoutInMinutes: 4
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = if (deploymentType == 'vm') {
  name: networkInterfaceName
  location: location
  properties: {
    enableAcceleratedNetworking: enableAcceleratedNetworking
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, subnetName)
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
  }
  tags: tags
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = if (deploymentType == 'vm') {
  name: vmName
  location: location
  tags: tags
  identity: enableSystemAssignedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: (platform == 'Linux'
        ? imageReference.Linux[ubuntuOSVersion]
        : imageReference.Windows[windowsOSVersion])
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: (platform == 'Windows' || (platform == 'Linux' && authenticationType == 'password')) ? adminPasswordOrKey : null
      linuxConfiguration: (platform == 'Linux' && authenticationType == 'sshPublicKey' ? linuxConfiguration : null)
      windowsConfiguration: (platform == 'Windows' ? windowsConfiguration : null)
    }
    diagnosticsProfile: enableBootDiagnostics ? {
      bootDiagnostics: {
        enabled: true
      }
    } : null
    securityProfile: (securityType == 'TrustedLaunch') ? securityProfileJson : null
  }
}

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (deploymentType == 'vm' && platform == 'Linux' && securityType == 'TrustedLaunch' && securityProfileJson.uefiSettings.secureBootEnabled && securityProfileJson.uefiSettings.vTpmEnabled) {
  parent: vm
  name: extensionName
  location: location
  properties: {
    publisher: extensionPublisher
    type: extensionName
    typeHandlerVersion: extensionVersion
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {
      AttestationConfig: {
        MaaSettings: {
          maaEndpoint: maaEndpoint
          maaTenantName: maaTenantName
        }
      }
    }
  }
}

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-07-01' = if (deploymentType == 'vmss') {
  name: vmName
  location: location
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: instanceCount
  }
  dependsOn: [
    loadBalancer
  ]
  tags: tags
  identity: enableSystemAssignedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    overprovision: true
    upgradePolicy: {
      mode: upgradePolicyMode
    }
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
        }
        imageReference: (platform == 'Linux'
          ? imageReference.Linux[ubuntuOSVersion]
          : imageReference.Windows[windowsOSVersion])
      }
      osProfile: {
        computerNamePrefix: vmName
        adminUsername: adminUsername
        adminPassword: (platform == 'Windows' || (platform == 'Linux' && authenticationType == 'password')) ? adminPasswordOrKey : null
        linuxConfiguration: (platform == 'Linux' && authenticationType == 'sshPublicKey' ? linuxConfiguration : null)
        windowsConfiguration: (platform == 'Windows' ? windowsConfiguration : null)
      }
      networkProfile: {
        healthProbe: {
          id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'vmssHealthProbe')
        }
        networkInterfaceConfigurations: [
          {
            name: networkInterfaceName
            properties: {
              enableAcceleratedNetworking: enableAcceleratedNetworking
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, subnetName)
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, bePoolName)
                      }
                    ]
                    loadBalancerInboundNatPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/inboundNatPools', lbName, natPoolName)
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      diagnosticsProfile: enableBootDiagnostics ? {
        bootDiagnostics: {
          enabled: true
        }
      } : null
    }
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = if (deploymentType == 'vmss') {
  name: lbName
  location: location
  sku: {
    name: 'Standard'
  }
  tags: tags
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: bePoolName
      }
    ]
    probes: [
      {
        name: 'vmssHealthProbe'
        properties: {
          protocol: 'Tcp'
          port: natBackendPort
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'vmssLBR'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, bePoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'vmssHealthProbe')
          }
          protocol: 'Tcp'
          frontendPort: lbRulePort
          backendPort: lbRulePort
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default'
        }
      }
    ]
    inboundNatPools: [
      {
        name: natPoolName
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
          }
          protocol: 'Tcp'
          frontendPortRangeStart: natStartPort
          frontendPortRangeEnd: natEndPort
          backendPort: natBackendPort
        }
      }
    ]
  }
}

resource autoScaleSettings 'Microsoft.Insights/autoscalesettings@2015-04-01' = if (deploymentType == 'vmss') {
  name: 'cpuautoscale'
  location: location
  tags: tags
  properties: {
    name: 'cpuautoscale'
    targetResourceUri: vmss.id
    enabled: true
    profiles: [
      {
        name: 'Profile1'
        capacity: {
          minimum: '1'
          maximum: '10'
          default: string(instanceCount)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: scaleOutThreshold
              statistic: 'Average'
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: scaleInThreshold
              statistic: 'Average'
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}

output fqdn string = publicIPAddress.properties.dnsSettings.fqdn
