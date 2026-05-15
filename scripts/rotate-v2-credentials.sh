#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
regions=(saopaulo rio brasilia)

for region in "${regions[@]}"; do
  file="$ROOT_DIR/secrets/runtime/$region/v2/processor.env"
  if [[ ! -f "$file" ]]; then
    echo "Missing $file - run scripts/bootstrap-secrets.sh first"
    exit 1
  fi

  tmp_file="${file}.tmp"
  cat > "$tmp_file" <<EOC
PROCESSOR_NAME=mock-bank-${region}
PROCESSOR_API_KEY=$(openssl rand -hex 20)
PROCESSOR_CERT_FINGERPRINT=$(openssl rand -hex 16)
EOC
  mv "$tmp_file" "$file"
  echo "Rotated credentials for v2 ($region)"
done

echo "Credentials rotated in-place for v2. Services pick changes via file watcher (no restart required)."
