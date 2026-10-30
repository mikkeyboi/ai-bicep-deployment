#!/usr/bin/env bash
# scripts/deploy-azure-mcp.sh - deploy the Azure MCP Claude connector (feature 016).
#
# Operator-run (not CI): the stack includes an Entra app registration, which
# needs directory permissions the GitHub OIDC principal does not hold.
#
# Sequence (same gates as deploy.ps1): verify az context -> seed the gateway
# master key in Key Vault if absent -> build the gateway image in ACR if the
# pinned tag is absent -> validate -> what-if -> (confirm) -> create.
#
# Usage:
#   scripts/deploy-azure-mcp.sh --environment dev --subscription <id> --tenant <id> [--what-if] [--yes]
#
# AZURE_MCP_ALLOWED_PRINCIPAL_IDS (comma-separated Entra object IDs) defaults
# to the signed-in operator. No flag defaults to a tenant or subscription.
set -euo pipefail

ENVIRONMENT="" SUBSCRIPTION="" TENANT="" WHAT_IF=0 YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment) ENVIRONMENT="$2"; shift 2 ;;
    --subscription) SUBSCRIPTION="$2"; shift 2 ;;
    --tenant) TENANT="$2"; shift 2 ;;
    --what-if) WHAT_IF=1; shift ;;
    --yes) YES=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$ENVIRONMENT" && -n "$SUBSCRIPTION" && -n "$TENANT" ]] || {
  echo "usage: $0 --environment <dev|test|prod> --subscription <id> --tenant <id> [--what-if] [--yes]" >&2; exit 2; }

mask() { local s="$1"; [[ ${#s} -lt 12 ]] && { echo "$s"; return; }; echo "${s:0:4}....${s: -4}"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_ROOT/infra/azure-mcp/main.bicep"
PARAMFILE="$REPO_ROOT/infra/parameters/azure-mcp.$ENVIRONMENT.bicepparam"
GATEWAY_SRC="$REPO_ROOT/apps/azure-mcp-gateway"
[[ -f "$PARAMFILE" ]] || { echo "parameter file not found: $PARAMFILE" >&2; exit 1; }

# --- az context ---
if [[ "$(az account show --query id -o tsv)" != "$SUBSCRIPTION" ]]; then
  echo "Setting active subscription to $(mask "$SUBSCRIPTION") ..."
  az account set --subscription "$SUBSCRIPTION"
fi
ACTIVE_TENANT="$(az account show --query tenantId -o tsv)"
[[ "$ACTIVE_TENANT" == "$TENANT" ]] || {
  echo "active az tenant ($(mask "$ACTIVE_TENANT")) does not match --tenant ($(mask "$TENANT")); run az login --tenant <id>" >&2; exit 1; }

if [[ -z "${AZURE_MCP_ALLOWED_PRINCIPAL_IDS:-}" ]]; then
  AZURE_MCP_ALLOWED_PRINCIPAL_IDS="$(az ad signed-in-user show --query id -o tsv)"
fi
export AZURE_MCP_ALLOWED_PRINCIPAL_IDS

# --- Resolve config from the compiled paramfile ---
PARAMS_JSON="$(bicep build-params "$PARAMFILE" --stdout | python3 -c 'import json,sys; print(json.load(sys.stdin)["parametersJson"])')"
# cfg <dotted.path> under config, e.g. cfg azureMcp.gatewayImageTag
cfg() {
  python3 -c 'import json,sys
v = json.loads(sys.argv[1])["parameters"]["config"]["value"]
for k in sys.argv[2].split("."): v = v[k]
print(v)' "$PARAMS_JSON" "$1"
}
WORKLOAD="$(cfg workloadName)"
ACR="$(cfg azureMcp.containerRegistryName)"
IMAGE_REPO="$(cfg azureMcp.gatewayImageRepository)"
IMAGE_TAG="$(cfg azureMcp.gatewayImageTag)"

RG="$(az group list --query "[?tags.workload=='$WORKLOAD' && tags.environment=='$ENVIRONMENT' && tags.managedBy=='bicep'].name | [0]" -o tsv)"
[[ -n "$RG" ]] || { echo "no resource group tagged workload=$WORKLOAD environment=$ENVIRONMENT; deploy infra/main.bicep first" >&2; exit 1; }
KV="$(az keyvault list -g "$RG" --query "[0].name" -o tsv)"
echo "Environment    : $ENVIRONMENT"
echo "Resource group : $RG"
echo "Allowed users  : $(echo "$AZURE_MCP_ALLOWED_PRINCIPAL_IDS" | tr ',' '\n' | while read -r p; do mask "$p"; done | paste -sd, -)"

# --- Gateway master key (generated once; never printed) ---
SECRET_NAME="azure-mcp-gateway-master-key"
if az keyvault secret show --vault-name "$KV" --name "$SECRET_NAME" --query id -o none 2>/dev/null; then
  echo "Master key     : present"
elif [[ $WHAT_IF -eq 1 ]]; then
  echo "Master key     : absent (would be created)"
else
  echo "Master key     : creating"
  KEYFILE="$(mktemp)"; trap 'rm -f "$KEYFILE"' EXIT
  chmod 600 "$KEYFILE"
  openssl rand -base64 48 | tr -d '\n' > "$KEYFILE"
  az keyvault secret set --vault-name "$KV" --name "$SECRET_NAME" --file "$KEYFILE" \
    --content-type "base64 key material for the Azure MCP gateway" --output none
  rm -f "$KEYFILE"
fi

# --- Gateway image (pinned tag; built in ACR only when missing) ---
if az acr manifest show-metadata --registry "$ACR" --name "$IMAGE_REPO:$IMAGE_TAG" -o none 2>/dev/null; then
  echo "Gateway image  : $IMAGE_REPO:$IMAGE_TAG present"
elif [[ $WHAT_IF -eq 1 ]]; then
  echo "Gateway image  : $IMAGE_REPO:$IMAGE_TAG absent (would be built)"
else
  echo "Gateway image  : building $IMAGE_REPO:$IMAGE_TAG in ACR"
  az acr build --registry "$ACR" --image "$IMAGE_REPO:$IMAGE_TAG" --platform linux/amd64 "$GATEWAY_SRC" --output none
fi

# --- validate -> what-if -> create ---
DEPLOY_NAME="azure-mcp-$ENVIRONMENT-$(date -u +%Y%m%d-%H%M%S)"
echo "Validating ..."
az deployment group validate -g "$RG" --template-file "$TEMPLATE" --parameters "$PARAMFILE" --output none
echo "What-if ..."
az deployment group what-if -g "$RG" --template-file "$TEMPLATE" --parameters "$PARAMFILE" --exclude-change-types Ignore NoChange
[[ $WHAT_IF -eq 1 ]] && { echo "--what-if set; stopping before create."; exit 0; }
if [[ $YES -ne 1 ]]; then
  read -r -p "Apply this deployment? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "aborted"; exit 1; }
fi
az deployment group create -g "$RG" --name "$DEPLOY_NAME" --template-file "$TEMPLATE" --parameters "$PARAMFILE" --output none
URL="$(az deployment group show -g "$RG" --name "$DEPLOY_NAME" --query properties.outputs.mcpServerUrl.value -o tsv)"
echo "deploy: SUCCESS  name=$DEPLOY_NAME"
echo "MCP server URL : $URL"
