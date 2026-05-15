#!/usr/bin/env bash
set -euo pipefail

DURATION_SECONDS="${1:-60}"
CONCURRENCY="${2:-10}"
END_TIME=$(( $(date +%s) + DURATION_SECONDS ))

endpoints=(
  "http://localhost:8001/authorize"
  "http://localhost:8002/authorize"
  "http://localhost:8003/authorize"
)

send_request() {
  local endpoint="$1"
  curl -s -o /dev/null -X POST "$endpoint" \
    -H 'Content-Type: application/json' \
    -d '{"amount":1250,"currency":"BRL","merchant_id":"merchant-demo"}' || true
}

while [[ $(date +%s) -lt $END_TIME ]]; do
  for endpoint in "${endpoints[@]}"; do
    for _ in $(seq 1 "$CONCURRENCY"); do
      send_request "$endpoint" &
    done
  done
  wait
  sleep 0.2
done

echo "Traffic generation finished: duration=${DURATION_SECONDS}s, concurrency=${CONCURRENCY}"
