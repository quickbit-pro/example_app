#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 64
fi

for required_command in python3 flutter; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Missing build dependency: $required_command" >&2
    exit 69
  fi
done
python3 -c 'import sys; sys.exit("Python 3.10 or newer is required" if sys.version_info < (3, 10) else 0)'

repository_directory="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
(
  cd "$repository_directory/mobile_flutter"
  flutter build web --release \
    --target lib/customer_preview_main.dart \
    --pwa-strategy none \
    --no-wasm-dry-run \
    --output build/customer_preview
)

python3 "$repository_directory/scripts/package-customer-preview.py" \
  "$repository_directory/mobile_flutter/build/customer_preview"
python3 "$repository_directory/scripts/build-customer-guide.py"
