param location string = resourceGroup().location
@secure()
param adminPassword string
param adminUsername string = 'sqluser'
var sqlServerName = 'sqlsrv${uniqueString(resourceGroup().id)}${location}'
var dbName = 'badActorDb'

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
  }
}

resource sqlServerDatabase 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: sqlServer
  name: dbName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}
