#!/usr/bin/env bash
# Thin wrapper — prefer: go run ./cmd/q22e ubuntu
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec go run ./cmd/q22e ubuntu "$@"
