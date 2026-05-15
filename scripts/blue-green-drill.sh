#!/usr/bin/env bash
set -euo pipefail

# Blue-Green drill:
# 1) Capture current phase
# 2) Switch target region(s) to full green (phase 4 = 100% v2)
# 3) Generate traffic for a test window
# 4) Sample responses and show version distribution
# 5) Roll back to requested phase (default: original detected phase, fallback phase 1)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${1:-all}"                       # saopaulo|rio|brasilia|all
TEST_DURATION_SECONDS="${2:-60}"          # traffic generation seconds
CONCURRENCY="${3:-10}"                    # per-endpoint concurrent requests
ROLLBACK_TO="${4:-auto}"                  # auto|1|2|3|4
SAMPLES_PER_REGION="${5:-40}"             # response samples per region for version distribution

regions=(saopaulo rio brasilia)
declare -A region_port=(
  [saopaulo]=8001
  [rio]=8002
  [brasilia]=8003
)

if [[ ! "$TARGET" =~ ^(all|saopaulo|rio|brasilia)$ ]]; then
  echo "Invalid target: $TARGET"
  echo "Usage: $0 [all|saopaulo|rio|brasilia] [duration_seconds] [concurrency] [rollback_to|auto] [samples_per_region]"
  exit 1
fi

if [[ ! "$ROLLBACK_TO" =~ ^(auto|1|2|3|4)$ ]]; then
  echo "Invalid rollback phase: $ROLLBACK_TO"
  exit 1
fi

selected_regions=()
if [[ "$TARGET" == "all" ]]; then
  selected_regions=("${regions[@]}")
else
  selected_regions=("$TARGET")
fi

# Keep original phases for auto-rollback
# shellcheck disable=SC2034
declare -A original_phase

extract_phase() {
  local region="$1"
  local port="${region_port[$region]}"
  local phase

  phase="$(curl -sS "http://localhost:${port}/rollout" | jq -r '.phase // empty' 2>/dev/null || true)"
  if [[ -z "$phase" || ! "$phase" =~ ^[1-4]$ ]]; then
    # Fallback to phase 1 if rollout endpoint is unavailable
    phase="1"
  fi
  echo "$phase"
}

sample_region_distribution() {
  local region="$1"
  local port="${region_port[$region]}"
  local samples="$2"

  echo "[${region}] sampling ${samples} authorization responses..."

  for _ in $(seq 1 "$samples"); do
    curl -sS -X POST "http://localhost:${port}/authorize" \
      -H 'Content-Type: application/json' \
      -d '{"amount":1000,"currency":"BRL","merchant_id":"drill"}' \
      | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown"
  done | sort | uniq -c | awk '{printf "  - %s => %s\n", $2, $1}'
}

rollback_phase_for() {
  local region="$1"
  if [[ "$ROLLBACK_TO" == "auto" ]]; then
    echo "${original_phase[$region]:-1}"
  else
    echo "$ROLLBACK_TO"
  fi
}

echo "=== Blue-Green Drill Start ==="
echo "Target: $TARGET"
echo "Test duration: ${TEST_DURATION_SECONDS}s"
echo "Concurrency: $CONCURRENCY"
echo "Rollback target: $ROLLBACK_TO"
echo

# Pre-check services
for region in "${selected_regions[@]}"; do
  port="${region_port[$region]}"
  if ! curl -fsS "http://localhost:${port}/health" >/dev/null; then
    echo "[ERROR] Router health check failed for region=$region (port=${port})."
    exit 1
  fi
  original_phase[$region]="$(extract_phase "$region")"
  echo "[$region] original phase: ${original_phase[$region]}"
done

echo
echo "[1/4] Switching selected region(s) to phase 4 (full green v2)..."
"$ROOT_DIR/scripts/rollout.sh" 4 "$TARGET"

echo
echo "[2/4] Generating traffic for ${TEST_DURATION_SECONDS}s..."
"$ROOT_DIR/scripts/generate-traffic.sh" "$TEST_DURATION_SECONDS" "$CONCURRENCY"

echo
echo "[3/4] Sampling version distribution after switch..."
for region in "${selected_regions[@]}"; do
  sample_region_distribution "$region" "$SAMPLES_PER_REGION"
done

echo
echo "[4/4] Rolling back selected region(s)..."
if [[ "$TARGET" == "all" ]]; then
  for region in "${selected_regions[@]}"; do
    phase="$(rollback_phase_for "$region")"
    "$ROOT_DIR/scripts/set-phase.sh" "$region" "$phase"
  done
else
  phase="$(rollback_phase_for "$TARGET")"
  "$ROOT_DIR/scripts/set-phase.sh" "$TARGET" "$phase"
fi

echo
echo "Post-rollback rollout status:"
for region in "${selected_regions[@]}"; do
  port="${region_port[$region]}"
  echo "- $region: $(curl -sS "http://localhost:${port}/rollout" || echo '{"error":"unavailable"}')"
done

echo
echo "=== Blue-Green Drill Complete ==="
