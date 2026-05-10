#!/usr/bin/env bash
# scripts/deploy.sh - thin wrapper that re-execs deploy.ps1 via pwsh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec pwsh -NoLogo -File "$SCRIPT_DIR/deploy.ps1" "$@"
