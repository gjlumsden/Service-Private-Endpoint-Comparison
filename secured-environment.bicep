param location string = resourceGroup().location
param vmUsername string = 'vmuser'
@secure()
param vmPassword string

@allowed([ 'Premium', 'Standard' ])
param firewallTier string = 'Standard'
param workspaceId string

@description('This is a temporary hack to prevent deployment errors on redeployment.')
param redeploy bool = true

var vmName = [for index in range(0, 2): 'vm${index}${index == 0 ? '-svc-ep' : '-non-svc-ep'}']
var firewallName = 'defw-${uniqueString(resourceGroup().name)}'
var firewallPipName = 'defw-pip-${uniqueString(resourceGroup().name)}'
var firewallPolicyName = 'defwp-${uniqueString(resourceGroup().name)}'
var vnetAddressPrefix = '172.16.0.0/16'

var seSubnetAddressPrefix = '172.16.0.0/24'
var seSubnetName = 'svc-endpoint-subnet'

var nonSeSubnetAddressPrefix = '172.16.1.0/24'
var nonSeSubnetName = 'non-svc-endpoint-subnet'

var peSubnetAddressPrefix = '172.16.2.0/24'
var peSubnetName = 'pvt-endpoint-subnet'

var bastionSubnetAddressPrefix = '172.16.3.0/24'
var bastionSubnetName = 'AzureBastionSubnet'

var fwSubnetAddressPrefix = '172.16.255.0/24'
var fwSubnetName = 'AzureFirewallSubnet'

var routeTableName = 'rt-${uniqueString(resourceGroup().name)}'
var bastionName = 'bstn-${uniqueString(resourceGroup().name)}'
var bastionPipName = 'bstn-pip-${uniqueString(resourceGroup().name)}'

var seStorageName = 'sestg${uniqueString(resourceGroup().name)}'

var peStorageName = 'pestg${uniqueString(resourceGroup().name)}'

var privateEndpointName = '${peStorageName}-pvtep'
var dnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var dnsZoneGroupName = '${privateEndpointName}/group'

resource defaultNsg 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: 'default-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowBastionInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetAddressPrefix
          sourcePortRange: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
          destinationAddressPrefixes: [
            seSubnetAddressPrefix
            nonSeSubnetAddressPrefix
          ]
        }
      }
    ]
  }
}

resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2020-11-01' = {
  name: 'bastion-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsInBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowGatewayManagerInBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'GatewayManager'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowLoadBalancerInBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBastionHostCommunicationInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSshRdpOutBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureCloudCommunicationOutBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionHostCommunicationOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowGetSessionInformationOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRanges: [
            '80'
            '443'
          ]
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

//dependsOn is used here to ensure the subnets don't deploy in parallel.
resource seSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' = {
  parent: virtualNetwork
  name: seSubnetName
  properties: {
    addressPrefix: seSubnetAddressPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
        locations: [
          location
        ]
      }
    ]
    routeTable: {
      id: routeTable.id
    }
    networkSecurityGroup: {
      id: defaultNsg.id
    }
  }
  dependsOn: [
    firewallSubnet
  ]
}

resource nonSeSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' = {
  parent: virtualNetwork
  name: nonSeSubnetName
  properties: {
    addressPrefix: nonSeSubnetAddressPrefix
    serviceEndpoints: [
      //None!
    ]
    routeTable: {
      id: routeTable.id
    }
    networkSecurityGroup: {
      id: defaultNsg.id
    }
  }
  dependsOn: [
    seSubnet
  ]
}

resource bstnSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' = {
  parent: virtualNetwork
  name: bastionSubnetName
  properties: {
    addressPrefix: bastionSubnetAddressPrefix
    serviceEndpoints: [
      //None!
    ]
    networkSecurityGroup: {
      id: bastionNsg.id
    }
  }
  dependsOn: [
    nonSeSubnet
  ]
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' = {
  parent: virtualNetwork
  name: fwSubnetName
  properties: {
    addressPrefix: fwSubnetAddressPrefix
    serviceEndpoints: [
      //None!
    ]
  }
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' = {
  parent: virtualNetwork
  name: peSubnetName
  properties: {
    addressPrefix: peSubnetAddressPrefix
    serviceEndpoints: [
      //None!
    ]
    networkSecurityGroup: {
      id: defaultNsg.id
    }
  }
  dependsOn: [
    firewallSubnet
  ]
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = if (!redeploy) {
  name: 'svc-pvt-endpoint-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

resource nics 'Microsoft.Network/networkInterfaces@2022-05-01' = [for index in range(0, 2): {
  name: 'nic${index}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: index == 0 ? seSubnet.id : nonSeSubnet.id
          }
        }
      }
    ]
  }
}]

resource vms 'Microsoft.Compute/virtualMachines@2020-12-01' = [for index in range(0, 2): {
  name: vmName[index]
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: vmName[index]
      adminUsername: vmUsername
      adminPassword: vmPassword
      windowsConfiguration: {
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
      osDisk: {
        name: 'vm${index}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[index].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}]

resource policyApplicationRuleGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-05-01' = {
  parent: firewallPolicy
  name: 'ApplicationRuleCollectionGroup'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'RuleCollection'
        priority: 200
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-Trusted-Storage-Accounts-Rules'
            protocols: [
              {
                protocolType: 'Https'
                port: 433
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              replace(replace(peStorage.properties.primaryEndpoints.blob, 'https://', ''), '/', '')
              replace(replace(seStorage.properties.primaryEndpoints.blob, 'https://', ''), '/', '')
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: [
              nonSeSubnetAddressPrefix
              seSubnetAddressPrefix
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-Microsoft'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
              {
                protocolType: 'Http'
                port: 80
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              '*.microsoft.com'
              '*.microsoftonline.com'
              '*.azure.com'
              '*.azure.net'
              '*.azureedge.net'
              '*.microsoft'
              '*.azure-dns.net'
              '*.azurewebsites.net'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: [
              nonSeSubnetAddressPrefix
              seSubnetAddressPrefix
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-Win-Update-Diagnostics'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            webCategories: []
            fqdnTags: [
              'WindowsUpdate'
              'WindowsDiagnostics'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: [
              nonSeSubnetAddressPrefix
              seSubnetAddressPrefix
            ]
          }
        ]
      }
    ]
  }
}

resource policyNetworkRuleGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2020-11-01' = {
  parent: firewallPolicy
  name: 'NetworkRuleCollectionGroup'
  dependsOn: [
    policyApplicationRuleGroup
  ]
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'DNS'
        action: {
          type: 'Allow'
        }
        priority: 310
        rules: [
          {
            ruleType: 'NetworkRule'
            sourceAddresses: [
              nonSeSubnetAddressPrefix
              seSubnetAddressPrefix
            ]
            destinationAddresses: [
              '*'
            ]
            destinationPorts: [
              '53'
            ]
            ipProtocols: [
              'TCP'
              'UDP'
            ]
            name: 'DNS'
            destinationIpGroups: []
            destinationFqdns: []
            sourceIpGroups: []
          }
          {
            ruleType: 'NetworkRule'
            sourceAddresses: [
              nonSeSubnetAddressPrefix
              seSubnetAddressPrefix
            ]
            destinationAddresses: [
              '40.83.235.53/32'
              '20.118.99.224/32'
              '23.102.135.246/32'
            ]
            destinationPorts: [
              '1688'
            ]
            ipProtocols: [
              'TCP'
              'UDP'
            ]
            name: 'Windows-Activation'
            destinationIpGroups: []
            destinationFqdns: []
            sourceIpGroups: []
          }
        ]
      }
    ]
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2020-11-01' = {
  name: firewallPolicyName
  location: location
  properties: {
    sku: {
      tier: firewallTier
    }
    insights: {
      isEnabled: true
      logAnalyticsResources: {
        defaultWorkspaceId: {
          id: workspaceId
        }
      }
    }
  }
}

resource fwPublicIp 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: firewallPipName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    ipTags: []
  }
  tags: {}
}

resource firewall 'Microsoft.Network/azureFirewalls@2022-05-01' = {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: firewallTier
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: '${firewallName}-ipconfig'
        properties: {
          subnet: {
            id: firewallSubnet.id
          }
          publicIPAddress: {
            id: fwPublicIp.id
          }
        }
      }
    ]
  }
}

resource firewallDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'log-analytics'
  scope: firewall
  properties: {
    storageAccountId: null
    eventHubAuthorizationRuleId: null
    eventHubName: null
    workspaceId: workspaceId
    logs: [
      {
        category: null
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
  }
}

resource routeTable 'Microsoft.Network/routeTables@2019-11-01' = {
  name: routeTableName
  location: location
  properties: {
    routes: [
      {
        name: 'route-to-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
    disableBgpRoutePropagation: true
  }
}

resource bstnPip 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: bastionPipName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    ipTags: []
  }
  tags: {}
}

resource bastion 'Microsoft.Network/bastionHosts@2022-05-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: bstnSubnet.id
          }
          publicIPAddress: {
            id: bstnPip.id
          }
        }
      }
    ]
  }
}

resource seStorage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: seStorageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: seSubnet.id
          action: 'Allow'
        }
      ]
    }
  }
}

resource peStorage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: peStorageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: peSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: peStorage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: dnsZoneName
  location: 'global'
  properties: {}
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${dnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource pvtEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: dnsZoneGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoint
  ]
}

output peStgFqdn string = peStorage.properties.primaryEndpoints.blob
output seStgFqdn string = seStorage.properties.primaryEndpoints.blob
