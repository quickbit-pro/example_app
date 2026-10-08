#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <brand.json> [flutter run options...]" >&2
  exit 64
fi
brand_file="$1"
shift
repository_directory="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
brand_directory="$(CDPATH= cd -- "$(dirname -- "$brand_file")" && pwd)"
brand_file="$brand_directory/$(basename -- "$brand_file")"
"${BRANDING_PYTHON:-python3}" "$repository_directory/scripts/prepare-mobile-brand.py" "$brand_file"
cd "$repository_directory/mobile_flutter"
flutter run --dart-define-from-file=.dart_tool/branding/defines.json "$@"
