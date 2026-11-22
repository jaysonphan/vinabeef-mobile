#!/usr/bin/env bash
# Generates the platform host projects around lib/ (flutter create never overwrites existing
# files), adds the AppAuth redirect scheme, and fetches packages.
# Usage (from vinabeef-mobile/):
#   ./scripts/bootstrap.sh              # android + ios
#   ./scripts/bootstrap.sh android      # only android
#   ./scripts/bootstrap.sh ios          # only ios (macOS + Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORMS="${1:-android,ios}"
SCHEME="vn.edu.hcmut.vinabeef"

if command -v fvm >/dev/null 2>&1; then FLUTTER=(fvm flutter); else FLUTTER=(flutter); fi
command -v "${FLUTTER[0]}" >/dev/null || { echo "Flutter SDK not found (need 3.35.x, see .fvmrc)"; exit 1; }

"${FLUTTER[@]}" create --org vn.edu.hcmut.vinabeef --project-name vinabeef_mobile --platforms "$PLATFORMS" .

# ---------- Android ----------
if [[ "$PLATFORMS" == *android* ]]; then
  GRADLE=android/app/build.gradle.kts
  [ -f "$GRADLE" ] || GRADLE=android/app/build.gradle
  if ! grep -q appAuthRedirectScheme "$GRADLE"; then
    if [[ "$GRADLE" == *.kts ]]; then
      perl -0pi -e 's/(defaultConfig\s*\{\n)/$1        manifestPlaceholders["appAuthRedirectScheme"] = "vn.edu.hcmut.vinabeef"\n/' "$GRADLE"
    else
      perl -0pi -e "s/(defaultConfig\s*\{\n)/\$1        manifestPlaceholders += [appAuthRedirectScheme: 'vn.edu.hcmut.vinabeef']\n/" "$GRADLE"
    fi
  fi
  grep -q appAuthRedirectScheme "$GRADLE" || { echo "Could not patch $GRADLE: add appAuthRedirectScheme manually (README)"; exit 1; }
fi

# ---------- iOS ----------
if [[ "$PLATFORMS" == *ios* ]]; then
  PLIST=ios/Runner/Info.plist
  PB=/usr/libexec/PlistBuddy
  if [ -x "$PB" ] && [ -f "$PLIST" ]; then
    # OAuth redirect scheme (vn.edu.hcmut.vinabeef:/oauthredirect)
    if ! "$PB" -c "Print :CFBundleURLTypes" "$PLIST" >/dev/null 2>&1; then
      "$PB" -c "Add :CFBundleURLTypes array" "$PLIST"
      "$PB" -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
      "$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
      "$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $SCHEME" "$PLIST"
    fi
    # Local dev: allow plain HTTP to localhost (compose stack). Remove for demo-tls/release.
    if ! "$PB" -c "Print :NSAppTransportSecurity" "$PLIST" >/dev/null 2>&1; then
      "$PB" -c "Add :NSAppTransportSecurity dict" "$PLIST"
      "$PB" -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST"
    fi
  else
    echo "iOS: PlistBuddy/Info.plist not found - add CFBundleURLTypes ($SCHEME) and NSAllowsLocalNetworking manually."
  fi
fi

"${FLUTTER[@]}" pub get

if [[ "$PLATFORMS" == *ios* ]]; then
  # pod install needs the iOS engine artifacts (Flutter.xcframework) in the Flutter cache.
  "${FLUTTER[@]}" precache --ios
  [ -f ios/Podfile ] && sed -i.bak "s/^# platform :ios, '13.0'/platform :ios, '13.0'/" ios/Podfile && rm -f ios/Podfile.bak
  if command -v pod >/dev/null 2>&1; then (cd ios && pod install); fi
fi

echo "OK. Next: ${FLUTTER[*]} test && ${FLUTTER[*]} run"
