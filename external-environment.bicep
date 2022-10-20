param location string = resourceGroup().location
var storageaccountname = 'badactor${uniqueString(resourceGroup().id)}'

resource storageaccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: storageaccountname
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}
