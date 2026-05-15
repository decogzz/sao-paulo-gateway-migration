#!/usr/bin/env bash
set -euo pipefail

regions=(saopaulo rio brasilia)
ports=(8001 8002 8003)

echo "=== Router health ==="
for i in "${!regions[@]}"; do
  region="${regions[$i]}"
  port="${ports[$i]}"
  echo "--- $region (:$port) ---"
  curl -sS "http://localhost:$port/health" || true
  echo
  curl -sS "http://localhost:$port/rollout" || true
  echo
  curl -sS -X POST "http://localhost:$port/authorize" -H 'Content-Type: application/json' -d '{"amount":1000,"currency":"BRL"}' || true
  echo
  echo
 done
