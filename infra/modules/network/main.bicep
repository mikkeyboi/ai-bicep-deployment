// modules/network/main.bicep
// Minimal VNet + delegated subnet for an ACA Consumption-only managed
// environment with internal ingress.
//
// Sizing: ACA Consumption-only environments require the infrastructure
// subnet to be /23 minimum (workload-profile envs allow /27, but we
// don't use workload profiles). The subnet must be delegated to
// Microsoft.App/environments and cannot host any other resources.
//
// This module is invoked behind the enableMatrix flag in workload.bicep,
// so disabling matrix tears the VNet down too (no orphan cost - VNets +
// empty subnets are free, but we keep the surface minimal anyway).

metadata description = 'VNet + /23 subnet delegated to Microsoft.App/environments for ACA internal ingress.'

param name string
param location string
param tags object

@description('Address space for the VNet. Defaults to a private /16 unlikely to clash with home/lab CIDRs.')
param vnetAddressPrefix string = '10.42.0.0/16'

@description('Subnet CIDR delegated to Microsoft.App/environments. Must be /23 or larger for Consumption-only ACA.')
param acaSubnetPrefix string = '10.42.0.0/23'

@description('Logical subnet name.')
param acaSubnetName string = 'aca-infra'

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
    subnets: [
      {
        name: acaSubnetName
        properties: {
          addressPrefix: acaSubnetPrefix
          delegations: [
            {
              name: 'aca-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          // Required so ACA control-plane traffic to Storage / KV / etc.
          // exits via service endpoints rather than forced through any
          // future hub.
          serviceEndpoints: [
            { service: 'Microsoft.Storage' }
            { service: 'Microsoft.KeyVault' }
          ]
        }
      }
    ]
  }
}

output id string = vnet.id
output name string = vnet.name
output acaSubnetId string = vnet.properties.subnets[0].id
output acaSubnetName string = acaSubnetName
