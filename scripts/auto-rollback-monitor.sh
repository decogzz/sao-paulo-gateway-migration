#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-saopaulo}"
CURRENT_PHASE="${2:-2}"
ROLLBACK_PHASE="${3:-1}"
THRESHOLD="${4:-0.02}"
PROM_URL="${PROM_URL:-http://localhost:9090}"
CHECK_INTERVAL="${CHECK_INTERVAL:-15}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

query='(sum(rate(gateway_requests_total{version="v2",region="'"$REGION"'",status="5xx",endpoint="/authorize"}[2m])) / sum(rate(gateway_requests_total{version="v2",region="'"$REGION"'",endpoint="/authorize"}[2m])))'
encoded_query="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$query")"

echo "Monitoring v2 error rate for region=$REGION (threshold=$THRESHOLD)"

while true; do
  response="$(curl -sS "$PROM_URL/api/v1/query?query=$encoded_query")"
  value="$(echo "$response" | jq -r '.data.result[0].value[1] // "0"')"

  echo "[$(date -Iseconds)] region=$REGION v2_error_rate=$value"

  exceeds="$(awk -v v="$value" -v t="$THRESHOLD" 'BEGIN {print (v > t) ? "yes" : "no"}')"

  if [[ "$exceeds" == "yes" ]]; then
    echo "Threshold exceeded. Triggering rollback to phase $ROLLBACK_PHASE"
    "$ROOT_DIR/scripts/set-phase.sh" "$REGION" "$ROLLBACK_PHASE"
    exit 0
  fi

  sleep "$CHECK_INTERVAL"
done
