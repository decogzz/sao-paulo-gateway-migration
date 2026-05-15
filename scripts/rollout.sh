#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <phase> [region|all]"
  exit 1
fi

PHASE="$1"
TARGET="${2:-all}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

regions=(saopaulo rio brasilia)

if [[ "$TARGET" == "all" ]]; then
  for region in "${regions[@]}"; do
    "$ROOT_DIR/scripts/set-phase.sh" "$region" "$PHASE"
  done
else
  "$ROOT_DIR/scripts/set-phase.sh" "$TARGET" "$PHASE"
fi

echo "Rollout update complete (phase=$PHASE, target=$TARGET)."
