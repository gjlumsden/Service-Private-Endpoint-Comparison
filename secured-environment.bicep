param location string = resourceGroup().location
param vmUsername string = 'vmuser'
@secure()
param vmPassword string

@allowed([ 'Premium', 'Standard' ])
param firewallTier string = 'Standard'
param workspaceId string

@secure()
param sqlAdminPassword string
param sqlAdminUsername string = 'sqluser'

var vmName = [for index in range(0, 2): 'vm${index}${index == 0 ? '-svc-ep' : 'non-svc-ep'}']
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

var seSqlServerName = 'se-sql-${uniqueString(resourceGroup().name)}'
var seSqlDbName = 'se-db'

var peSqlServerName = 'pe-sql-${uniqueString(resourceGroup().name)}'
var peSqlDbName = 'pe-db'

var privateEndpointName = '${peSqlServerName}-pvtep'
var dnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'
var dnsZoneGroupName = '${privateEndpointName}/group'

//dependsOn is used here to ensure the subnets don't deploy in parallel.
resource seSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' = {
  parent: virtualNetwork
  name: seSubnetName
  properties: {
    addressPrefix: seSubnetAddressPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.Sql'
        locations: [
          location
        ]
      }
    ]
    routeTable: {
      id: routeTable.id
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
  }
  dependsOn: [
    firewallSubnet
  ]
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
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
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'AzureMonitorRuleCollection'
        priority: 300
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-Trusted-SQL-Rules'
            protocols: [
              {
                protocolType: 'mssql'
                port: 1433
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              seSqlServer.properties.fullyQualifiedDomainName
              peSqlServer.properties.fullyQualifiedDomainName
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: [
              peSubnetAddressPrefix
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
              '*.windows.net'
              '*.azure-dns.net'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: [
              peSubnetAddressPrefix
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
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'DNS'
        action: {
          type: 'Allow'
        }
        priority: 210
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

resource routeTable 'Microsoft.Network/routeTables@2019-11-01' = {
  name: routeTableName
  location: location
  properties: {
    routes: [
      {
        name: 'name'
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

resource seSqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: seSqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
  }
}

resource seSqlServerVnetRule 'Microsoft.Sql/servers/virtualNetworkRules@2021-11-01' = {
  parent: seSqlServer
  name: 'allow-se-subnet'
  properties: {
    virtualNetworkSubnetId: seSubnet.id
  }
}

resource seDatabase 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: seSqlServer
  name: seSqlDbName
  location: location
  properties: {
    sampleName: 'AdventureWorksLT'
  }
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

resource peSqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: peSqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
  }
}

resource peDatabase 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: peSqlServer
  name: peSqlDbName
  location: location
  properties: {
    sampleName: 'AdventureWorksLT'
  }
  sku: {
    name: 'Standard'
    tier: 'Standard'
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
          privateLinkServiceId: peSqlServer.id
          groupIds: [
            'sqlServer'
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
