#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <apk|appbundle|ios|ipa|web> <brand.json> [flutter build options...]" >&2
  exit 64
fi
build_target="$1"
brand_file="$2"
shift 2
case "$build_target" in
  apk|appbundle|ios|ipa|web) ;;
  *) echo "Unsupported Flutter build target: $build_target" >&2; exit 64 ;;
esac
repository_directory="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
brand_directory="$(CDPATH= cd -- "$(dirname -- "$brand_file")" && pwd)"
brand_file="$brand_directory/$(basename -- "$brand_file")"
# Flutter resolves custom web output paths relative to mobile_flutter.
web_output="build/web"
expect_output=false
for option in "$@"; do
  if [[ "$expect_output" == true ]]; then
    web_output="$option"
    expect_output=false
    continue
  fi
  case "$option" in
    --output|--output-dir|-o) expect_output=true ;;
    --output=*|--output-dir=*|-o=*) web_output="${option#*=}" ;;
  esac
done
python_command="${BRANDING_PYTHON:-python3}"
"$python_command" "$repository_directory/scripts/prepare-mobile-brand.py" "$brand_file"
cd "$repository_directory/mobile_flutter"
flutter build "$build_target" --dart-define-from-file=.dart_tool/branding/defines.json "$@"
if [[ "$build_target" == web ]]; then
  "$python_command" "$repository_directory/scripts/prepare-mobile-brand.py" --finalize-web "$web_output"
fi
