// modules/matrix/homeserver.bicep
// Container App running continuwuity (Matrix homeserver) + optional
// cloudflared sidecar. Ingress is internal-only; the cloudflared tunnel
// is the only public path.

metadata description = 'Continuwuity homeserver Container App with optional cloudflared sidecar.'

param name string
param location string
param tags object

param environmentId string
param userAssignedIdentityResourceId string
param userAssignedIdentityClientId string
param keyVaultUri string

@description('Pinned continuwuity image, e.g. forgejo.ellis.link/continuwuation/continuwuity:v0.5.5')
param continuwuityImage string

@description('Pinned cloudflared image, e.g. docker.io/cloudflare/cloudflared:2026.3.0')
param cloudflaredImage string

@description('Cloudflare Tunnel sidecar gate. False = continuwuity only.')
param enableCloudflareTunnel bool

@minLength(1)
@description('Matrix server_name. Sourced from $env:MATRIX_HOSTNAME; MUST be non-empty (Constitution II).')
param serverName string

@minValue(0)
@maxValue(5)
param minReplicas int = 1
@minValue(1)
@maxValue(5)
param maxReplicas int = 1

param homeserverCpu string = '0.5'
param homeserverMemory string = '1Gi'
param cloudflaredCpu string = '0.25'
param cloudflaredMemory string = '0.5Gi'

param storageMountName string = 'continuwuity-data'

var tunnelSecretName = 'cloudflare-tunnel-token'

var cloudflaredContainer = {
  name: 'cloudflared'
  image: cloudflaredImage
  args: [
    'tunnel'
    '--no-autoupdate'
    'run'
  ]
  resources: {
    cpu: json(cloudflaredCpu)
    memory: cloudflaredMemory
  }
  env: [
    {
      name: 'TUNNEL_TOKEN'
      secretRef: tunnelSecretName
    }
  ]
}

var continuwuityContainer = {
  name: 'continuwuity'
  image: continuwuityImage
  resources: {
    cpu: json(homeserverCpu)
    memory: homeserverMemory
  }
  env: [
    { name: 'CONTINUWUITY_SERVER_NAME', value: serverName }
    { name: 'CONTINUWUITY_DATABASE_PATH', value: '/var/lib/continuwuity' }
    { name: 'CONTINUWUITY_ADDRESS', value: '0.0.0.0' }
    { name: 'CONTINUWUITY_PORT', value: '8008' }
    { name: 'CONTINUWUITY_ALLOW_FEDERATION', value: 'false' }
    { name: 'CONTINUWUITY_ALLOW_REGISTRATION', value: 'false' }
    { name: 'CONTINUWUITY_ALLOW_CHECK_FOR_UPDATES', value: 'false' }
  ]
  volumeMounts: [
    {
      volumeName: 'data'
      mountPath: '/var/lib/continuwuity'
    }
  ]
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8008
        transport: 'auto'
        allowInsecure: false
      }
      secrets: enableCloudflareTunnel ? [
        {
          name: tunnelSecretName
          keyVaultUrl: '${keyVaultUri}secrets/${tunnelSecretName}'
          identity: userAssignedIdentityResourceId
        }
      ] : []
    }
    template: {
      containers: enableCloudflareTunnel
        ? [ continuwuityContainer, cloudflaredContainer ]
        : [ continuwuityContainer ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
      volumes: [
        {
          name: 'data'
          storageType: 'AzureFile'
          storageName: storageMountName
        }
      ]
    }
  }
}

#disable-next-line outputs-should-not-contain-secrets
output id string = app.id
output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
output clientId string = userAssignedIdentityClientId
