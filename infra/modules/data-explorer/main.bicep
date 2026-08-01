// modules/data-explorer/main.bicep
metadata description = 'Azure Data Explorer cluster + database for agent-run telemetry.'

// The telemetry store for the agent workflow: one row per triage decision and
// one per agent turn or tool call. It is declared here rather than clicked
// together in the portal for the same reason the agent definitions are yaml --
// a portal-created cluster has no diff, no review, and no rollback.
//
// Schema (tables, functions, dashboard queries) is NOT provisioned here. KQL
// DDL is a data-plane operation that ARM cannot express, so it stays in the
// consuming repo's `kql/schema.kql` applied by an idempotent script. This
// module owns the control plane only, and the split is deliberate: mixing a
// data-plane script into an ARM deployment makes both harder to re-run safely.

param name string
param location string
param tags object

@description('Cluster SKU. Dev(No SLA)_Standard_E2a_v4 is the single-node development tier -- cheap, no availability guarantee, and explicitly not for production. Capacity is forced to 1 for it because the dev tier cannot scale out.')
param skuName string = 'Dev(No SLA)_Standard_E2a_v4'

@allowed(['Basic', 'Standard'])
param skuTier string = 'Basic'

@description('Node count. Ignored (forced to 1) on the dev tier.')
@minValue(1)
@maxValue(1000)
param capacity int = 1

param databaseName string = 'hvac'

@description('How long queryable data is retained. The agent telemetry is a benchmark artifact, not a compliance record, so this is short by intent.')
param softDeletePeriod string = 'P31D'

@description('How long data stays in the hot (SSD-backed, fastest) cache.')
param hotCachePeriod string = 'P7D'

@description('Streaming ingestion. Required for the dashboard to be live rather than lagging a batch window -- rows are queryable in seconds instead of minutes.')
param enableStreamingIngest bool = true

@description('Public network access. The dev cluster is reachable from the operator workstation and from GitHub-hosted runners, neither of which sits in the VNet.')
param publicNetworkAccess string = 'Enabled'

var isDevSku = startsWith(skuName, 'Dev(No SLA)')

resource cluster 'Microsoft.Kusto/clusters@2024-04-13' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
    // The dev tier rejects any capacity above 1, so the guard lives here
    // rather than relying on the caller to remember it.
    capacity: isDevSku ? 1 : capacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enableStreamingIngest: enableStreamingIngest
    enablePurge: false
    enableDoubleEncryption: false
    publicNetworkAccess: publicNetworkAccess
    // Local (key-based) auth has no equivalent here; ADX is Entra-only for
    // both query and management, which is why no key handling appears above.
  }
}

resource database 'Microsoft.Kusto/clusters/databases@2024-04-13' = {
  parent: cluster
  name: databaseName
  location: location
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: softDeletePeriod
    hotCachePeriod: hotCachePeriod
  }
}

output id string = cluster.id
output name string = cluster.name
output uri string = cluster.properties.uri
output dataIngestionUri string = cluster.properties.dataIngestionUri
output databaseName string = database.name
output databaseId string = database.id
output principalId string = cluster.identity.principalId
