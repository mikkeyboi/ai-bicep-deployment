// infra/shared/naming.bicep
// CAF-compliant resource naming via user-defined functions.
// Pattern: <abbr>-<workload>-<env>-<regionShort>[-<instance>][-<hash>]

metadata description = 'Central naming functions implementing CAF abbreviations.'

// --------- Region short codes ---------

var regionMap = {
  eastus: 'eus'
  eastus2: 'eus2'
  westus: 'wus'
  westus2: 'wus2'
  westus3: 'wus3'
  centralus: 'cus'
  northcentralus: 'ncus'
  southcentralus: 'scus'
  westcentralus: 'wcus'
  canadacentral: 'cac'
  canadaeast: 'cae'
  northeurope: 'neu'
  westeurope: 'weu'
  uksouth: 'uks'
  ukwest: 'ukw'
  francecentral: 'frc'
  germanywestcentral: 'gwc'
  switzerlandnorth: 'chn'
  swedencentral: 'sdc'
  norwayeast: 'nwe'
  eastasia: 'ea'
  southeastasia: 'sea'
  japaneast: 'jpe'
  japanwest: 'jpw'
  australiaeast: 'aue'
  australiasoutheast: 'ause'
  brazilsouth: 'brs'
  centralindia: 'cin'
  southindia: 'sin'
  koreacentral: 'krc'
  uaenorth: 'uan'
  southafricanorth: 'san'
}

@export()
@description('Short code for an Azure region, e.g. "eastus2" -> "eus2".')
func regionShort(location string) string => contains(regionMap, location) ? regionMap[location] : 'unk'

// --------- Internal builders ---------

@export()
@description('Build a CAF-style resource name with optional instance suffix.')
func nameOf(abbr string, workload string, env string, location string, instance string) string =>
  empty(instance)
    ? '${abbr}-${workload}-${env}-${regionShort(location)}'
    : '${abbr}-${workload}-${env}-${regionShort(location)}-${instance}'

@export()
@description('Append a deterministic 5-char hash for globally-unique resource names.')
func nameOfUnique(abbr string, workload string, env string, location string, instance string, uniqueSeed string) string =>
  empty(instance)
    ? '${abbr}-${workload}-${env}-${regionShort(location)}-${take(uniqueString(uniqueSeed), 5)}'
    : '${abbr}-${workload}-${env}-${regionShort(location)}-${instance}-${take(uniqueString(uniqueSeed), 5)}'

// --------- Per-resource helpers ---------

@export()
func rg(workload string, env string, location string, instance string) string =>
  nameOf('rg', workload, env, location, instance)

@export()
func law(workload string, env string, location string, instance string) string =>
  nameOf('log', workload, env, location, instance)

@export()
func ai(workload string, env string, location string, instance string) string =>
  nameOf('appi', workload, env, location, instance)

@export()
func mi(workload string, env string, location string, instance string) string =>
  nameOf('id', workload, env, location, instance)

@export()
func openai(workload string, env string, location string, instance string, uniqueSeed string) string =>
  nameOfUnique('oai', workload, env, location, instance, uniqueSeed)

@export()
func foundry(workload string, env string, location string, instance string, uniqueSeed string) string =>
  nameOfUnique('aif', workload, env, location, instance, uniqueSeed)

@export()
func foundryHub(workload string, env string, location string, instance string) string =>
  nameOf('hub', workload, env, location, instance)

@export()
func project(workload string, env string, location string, instance string) string =>
  nameOf('proj', workload, env, location, instance)

@export()
func search(workload string, env string, location string, instance string, uniqueSeed string) string =>
  nameOfUnique('srch', workload, env, location, instance, uniqueSeed)

@export()
@description('Container Apps Environment.')
func cae(workload string, env string, location string, instance string) string =>
  nameOf('cae', workload, env, location, instance)

@export()
@description('Container App.')
func ca(workload string, env string, location string, instance string) string =>
  nameOf('ca', workload, env, location, instance)

@export()
@description('Key Vault: 3-24 chars, alphanumeric + hyphen, must start with letter.')
func kv(workload string, env string, location string, instance string, uniqueSeed string) string =>
  take(nameOfUnique('kv', workload, env, location, instance, uniqueSeed), 24)

@export()
@description('Storage account: 3-24 lowercase alphanumeric, no hyphens.')
func storage(workload string, env string, location string, instance string, uniqueSeed string) string =>
  toLower(take(replace(nameOfUnique('st', workload, env, location, instance, uniqueSeed), '-', ''), 24))
