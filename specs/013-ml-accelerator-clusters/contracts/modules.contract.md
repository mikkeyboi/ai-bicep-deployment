# Module contract: accelerator cluster naming

## Shared type

`amlComputeClusterConfig` gains:

```text
nameSuffix: string?
```

The field is optional. Existing configurations that omit it must compile to their current names.

## Workload resolution

For each configured cluster, `workload.bicep` passes this instance segment to the central naming helper:

1. `nameSuffix` when provided;
2. otherwise `processor`.

The resolved record passed to `modules/machine-learning/compute.bicep` remains:

- name
- VM size
- priority
- scale settings

## Compute module

No accelerator-specific logic is permitted. It continues to create generic Linux AmlCompute clusters with the supplied resolved values, system-assigned identity, scale settings, and disabled remote login.

## Compatibility

- Existing CPU and V100 names are byte-for-byte unchanged.
- Test/prod parameter files that omit `machineLearning` remain valid.
- New accelerator labels and SKU literals exist only in the dev parameter file.
