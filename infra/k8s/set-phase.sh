#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-}"
PHASE="${2:-}"

if [[ -z "$REGION" || -z "$PHASE" ]]; then
  echo "Usage: $0 <saopaulo|rio|brasilia> <1|2|3|4>"
  exit 1
fi

if [[ ! "$REGION" =~ ^(saopaulo|rio|brasilia)$ ]]; then
  echo "Invalid region: $REGION"
  exit 1
fi

if [[ ! "$PHASE" =~ ^[1-4]$ ]]; then
  echo "Invalid phase: $PHASE"
  exit 1
fi

case "$PHASE" in
  1) WEIGHT=10 ;;
  2) WEIGHT=50 ;;
  3) WEIGHT=90 ;;
  4) WEIGHT=100 ;;
esac

NAMESPACE="gateway-${REGION}"

echo "Setting canary weight for region=${REGION} (namespace=${NAMESPACE}) to ${WEIGHT}%"
kubectl -n "$NAMESPACE" annotate ingress gateway-canary nginx.ingress.kubernetes.io/canary-weight="$WEIGHT" --overwrite

echo "Done."
