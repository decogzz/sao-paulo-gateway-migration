#!/usr/bin/env bash
set -euo pipefail

# Ensure generated credentials are private on disk.
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/secrets/runtime"

regions=(saopaulo rio brasilia)
versions=(v1 v2)

for region in "${regions[@]}"; do
  for version in "${versions[@]}"; do
    dir="$RUNTIME_DIR/$region/$version"
    mkdir -p "$dir"

    tmp_file="$dir/processor.env.tmp"

    cat > "$tmp_file" <<EOC
PROCESSOR_NAME=mock-bank-${region}
PROCESSOR_API_KEY=$(openssl rand -hex 20)
PROCESSOR_CERT_FINGERPRINT=$(openssl rand -hex 16)
EOC

    mv "$tmp_file" "$dir/processor.env"
  done
done

echo "Generated runtime credentials in $RUNTIME_DIR (files are gitignored and mode-restricted)."
