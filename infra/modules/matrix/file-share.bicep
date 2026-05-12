// modules/matrix/file-share.bicep
// Azure Files share on an existing storage account, used by the
// continuwuity container for its RocksDB state.

metadata description = 'Azure Files share on an existing storage account for continuwuity persistent state.'

param storageAccountName string
param shareName string
@minValue(1)
@maxValue(102400)
param quotaGiB int = 5

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: sa
  name: 'default'
  properties: {}
}

resource share 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileServices
  name: shareName
  properties: {
    accessTier: 'TransactionOptimized'
    shareQuota: quotaGiB
    enabledProtocols: 'SMB'
  }
}

output shareName string = share.name
output id string = share.id
