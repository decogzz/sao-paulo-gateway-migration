#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
regions=(saopaulo rio brasilia)
phases=(1 2 3 4)

for region in "${regions[@]}"; do
  echo "===== Starting rollout for $region ====="
  for phase in "${phases[@]}"; do
    "$ROOT_DIR/scripts/set-phase.sh" "$region" "$phase"
    echo "Region=$region moved to phase=$phase"
    echo "Validate metrics before proceeding. Press Enter to continue..."
    read -r
  done
  echo "===== $region fully migrated to v2 ====="
done
