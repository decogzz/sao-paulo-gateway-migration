#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <target-region|all> <rollback-to-phase>"
  exit 1
fi

TARGET="$1"
PHASE="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/rollout.sh" "$PHASE" "$TARGET"

echo "Rollback executed: target=$TARGET phase=$PHASE"
