#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <region> <phase>"
  echo "Regions: saopaulo | rio | brasilia"
  echo "Phases: 1 | 2 | 3 | 4"
  exit 1
fi

REGION="$1"
PHASE="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! "$REGION" =~ ^(saopaulo|rio|brasilia)$ ]]; then
  echo "Invalid region: $REGION"
  exit 1
fi

if [[ ! "$PHASE" =~ ^[1-4]$ ]]; then
  echo "Invalid phase: $PHASE"
  exit 1
fi

SOURCE_CONF="$ROOT_DIR/nginx/regions/$REGION/phases/phase${PHASE}.conf"
TARGET_CONF="$ROOT_DIR/nginx/regions/$REGION/active.conf"

cp "$SOURCE_CONF" "$TARGET_CONF"
echo "[$REGION] switched local active.conf to phase $PHASE"

cd "$ROOT_DIR"
if docker compose ps --status running "router-$REGION" >/dev/null 2>&1; then
  docker compose exec -T "router-$REGION" nginx -s reload
  echo "[$REGION] nginx reloaded"
else
  echo "[$REGION] router container not running yet. Change will apply on next startup."
fi
