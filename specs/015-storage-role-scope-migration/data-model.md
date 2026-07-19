# Data model: scope-specific role identity

| Grant | GUID inputs | Migration behavior |
|---|---|---|
| resource group | scope resource ID, principal ID, role ID | unchanged |
| storage account | `storageAccount`, scope resource ID, principal ID, role ID | new additive identity |

The scope-kind discriminator is part of resource identity, not user metadata.
Role properties and privileges are unchanged.
