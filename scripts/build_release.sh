#!/usr/bin/env bash
# Builds the STORE artifacts with analytics actually switched on, and proves it.
#
# Why this script exists: analytics.dart is off unless ANALYTICS_ENABLED and
# UMAMI_WEBSITE_ID are passed at build time — deliberately, so a build from the public
# source reports nothing. The consequence is that a plain `flutter build` produces a
# store artifact that silently measures nothing, and that is exactly what happened:
# app.kolichka.gotvach.com recorded 0 visitors across every release up to and including
# 1.6.2, while the website recorded 2012 over the same period.
#
# So the flags live here rather than in someone's shell history, and the build FAILS if
# the property id did not reach the compiled snapshot.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .analytics.env ] || { echo "✗ .analytics.env missing — see the header of this script"; exit 1; }
set -a; . ./.analytics.env; set +a
[ -n "${UMAMI_WEBSITE_ID:-}" ] || { echo "✗ UMAMI_WEBSITE_ID empty in .analytics.env"; exit 1; }

APP_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | cut -d+ -f1)
DEFINES=(
  --dart-define=ANALYTICS_ENABLED=true
  --dart-define=UMAMI_WEBSITE_ID="$UMAMI_WEBSITE_ID"
  --dart-define=APP_VERSION="$APP_VERSION"
)
echo "→ building $APP_VERSION with analytics ON (property ${UMAMI_WEBSITE_ID:0:8}…)"

flutter build appbundle --release "${DEFINES[@]}"
flutter build apk       --release "${DEFINES[@]}"
flutter build ipa       --release "${DEFINES[@]}" --export-options-plist=ios/ExportOptions.plist

# ── prove the define reached the binaries ──────────────────────────────────────
# A dart-define is compiled into the snapshot as a plain string, so the property id has
# to be findable in it. Dart AOT stores strings as UTF-16LE on iOS and UTF-8 inside the
# Android .so, so check BOTH encodings — a UTF-8-only grep gives a false negative and
# would "prove" a working build was broken.
fail=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

extract() {  # extract <archive> <suffix> <out>
  python3 - "$1" "$2" "$3" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.endswith(sys.argv[2]):
        open(sys.argv[3], 'wb').write(z.read(n)); break
PY
}

check() {  # check <label> <file>
  local label="$1" file="$2"
  [ -s "$file" ] || { echo "  ✗ $label: could not extract the snapshot"; fail=1; return; }
  if grep -qa "$UMAMI_WEBSITE_ID" "$file" \
     || grep -qa "$(printf '%s' "$UMAMI_WEBSITE_ID" | iconv -f UTF-8 -t UTF-16LE)" "$file"; then
    echo "  ✓ $label: analytics property present"
  else
    echo "  ✗ $label: property NOT in the binary — analytics would be silently OFF"
    fail=1
  fi
}

extract build/app/outputs/bundle/release/app-release.aab libapp.so       "$TMP/libapp.so"
check   "Android (libapp.so)"        "$TMP/libapp.so"
extract build/ios/ipa/kolichka.ipa   App.framework/App    "$TMP/App"
check   "iOS (App.framework/App)"    "$TMP/App"

[ "$fail" = 0 ] || { echo "✗ refusing to ship a build that cannot report"; exit 1; }
echo "✓ $APP_VERSION built, analytics verified in both binaries"
