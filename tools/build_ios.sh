#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "IPA creation requires macOS and Xcode. No IPA was created." >&2
  exit 1
fi
cd "$(dirname "$0")/.."
method="${1:-ad-hoc}"
case "$method" in
  ad-hoc|development|app-store) ;;
  *) echo "Usage: bash tools/build_ios.sh [ad-hoc|development|app-store]" >&2; exit 1 ;;
esac
for tool in flutter xcodebuild pod; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
xcodebuild -version
if [[ ! -f config/firebase.ios.json ]]; then
  echo "Copy config/firebase.ios.json from the configured workspace first." >&2
  exit 1
fi
flutter pub get
(cd ios && pod install)
settings="$(xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -showBuildSettings)"
if ! printf '%s\n' "$settings" | grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM = [A-Za-z0-9]+'; then
  echo "Open ios/Runner.xcworkspace in Xcode and select Runner > Signing & Capabilities > Team." >&2
  exit 1
fi
flutter build ipa --release \
  --dart-define-from-file=config/firebase.ios.json \
  --export-method="$method"
shopt -s nullglob
ipas=(build/ios/ipa/*.ipa)
if (( ${#ipas[@]} == 0 )); then
  echo "IPA export failed. Review the Xcode signing/export error above." >&2
  exit 1
fi
printf 'IPA: %s\n' "${ipas[@]}"
