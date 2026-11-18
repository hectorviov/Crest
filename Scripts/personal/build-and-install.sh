#!/bin/zsh
set -euo pipefail

# Personal build of Crest's dual-engine (WebKit + Chromium) Mac app, signed
# with *your own* Developer ID instead of the maintainer's.
#
# Adapted from Scripts/install-local-macos-release.sh. Differences:
#   - Signs with the first "Developer ID Application" identity in your
#     keychain (override with CREST_SIGNING_TEAM=XXXXXXXXXX).
#   - No provisioning profile, so the entitlements only Crest's own team can
#     have are left out: iCloud sync, push, the team keychain group (Crest's
#     built-in password store) and the browser passkey entitlement.
#   - Uses a very high build number so Sparkle never "updates" this build
#     back to the official one. Override with CREST_LOCAL_BUILD_NUMBER.
#   - Backs up ~/Library/Application Support/Crest and the preferences before
#     replacing /Applications/Crest.app, and keeps the previous app.
#
# Usage:
#   Scripts/personal/build-and-install.sh            # build only
#   Scripts/personal/build-and-install.sh --install  # build, back up, install

repository_root="${0:A:h:h:h}"
cd "$repository_root"

install=false
[[ "${1:-}" == "--install" ]] && install=true

application_path="/Applications/Crest.app"
repository="pauljoda/Crest"
build_number="${CREST_LOCAL_BUILD_NUMBER:-900000}"
personal_root="${CREST_PERSONAL_ROOT:-$HOME/Library/Caches/Crest-personal}"
derived_data_path="$personal_root/DerivedData"
engine_cache_root="$personal_root/engines"
output_path="$personal_root/product/Crest.app"
backup_root="${CREST_BACKUP_ROOT:-$HOME/Crest-backups}"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# --- Signing identity ---
team_filter="${CREST_SIGNING_TEAM:-[A-Z0-9]+}"
signing_line="$(security find-identity -v -p codesigning \
  | grep -E "\"Developer ID Application: .*\\(${team_filter}\\)\"" | head -1 || true)"
if [[ -z "$signing_line" ]]; then
  print -u2 "No Developer ID Application identity found (team filter: $team_filter)."
  exit 1
fi
signing_identity_hash="$(print -r -- "$signing_line" | awk '{print $2}')"
print "Signing with: ${signing_line#*\"}"

# --- Tools ---
dotnet=""
for candidate in "${CREST_DOTNET:-}" "$HOME/.dotnet/dotnet" "$(command -v dotnet || true)" /usr/local/share/dotnet/dotnet; do
  if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" --list-sdks | grep -q '^10\.0\.'; then
    dotnet="$candidate"
    break
  fi
done
if [[ -z "$dotnet" ]]; then
  print -u2 "Install the .NET 10 SDK: Scripts/control-plane/install-dotnet.sh"
  exit 1
fi
export DOTNET_ROOT="${dotnet:h}" PATH="${dotnet:h}:$PATH"
command -v xcodegen >/dev/null || { print -u2 "Install XcodeGen (brew install xcodegen)."; exit 1; }
command -v gh >/dev/null || { print -u2 "Install the GitHub CLI (brew install gh)."; exit 1; }

work_root="$(mktemp -d "${TMPDIR%/}/crest-personal.XXXXXX")"
trap 'find "$work_root" -depth -delete 2>/dev/null || true' EXIT INT TERM HUP

# --- Chromium engine: the published one matching this checkout's inputs ---
if [[ -n "${CREST_CHROMIUM_APP:-}" ]]; then
  engine_path="${CREST_CHROMIUM_APP:A}"
else
  engine_tag="$(python3 Scripts/control-plane/chromium_engine.py tag)"
  engine_asset="$(python3 Scripts/control-plane/chromium_engine.py asset)"
  engine_path="$engine_cache_root/$engine_tag/Chromium.app"
  if [[ ! -d "$engine_path" ]]; then
    print "Downloading Chromium engine $engine_tag..."
    download_path="$work_root/engine-download"
    mkdir -p "$download_path"
    if ! gh release download "$engine_tag" --repo "$repository" \
      --pattern "$engine_asset" --pattern "${engine_asset}.sha256" --dir "$download_path"; then
      print -u2 "No published Chromium engine for this checkout ($engine_tag)."
      print -u2 "Your changes probably touch engine inputs; see CrestEngines/Chromium/README.md."
      exit 1
    fi
    (cd "$download_path" && shasum -a 256 -c "${engine_asset}.sha256")
    ditto -x -k "$download_path/$engine_asset" "$download_path/extracted"
    [[ -d "$download_path/extracted/Chromium.app" ]]
    mkdir -p "$engine_cache_root"
    find "$engine_cache_root" -mindepth 1 -maxdepth 1 -name 'chromium-engine-*' -exec rm -rf {} + 2>/dev/null || true
    mv "$download_path/extracted" "$engine_cache_root/$engine_tag"
  fi
fi
[[ -f "$engine_path/Contents/Info.plist" ]] || { print -u2 "No Chromium.app at $engine_path."; exit 1; }

# --- Crest: native core + Chromium UI framework ---
xcodegen generate --quiet
(cd CrestCore && "$dotnet" publish src/CrestCore.Native -c Release -r osx-arm64 --nologo -v quiet)
core_library="$PWD/CrestCore/src/CrestCore.Native/bin/Release/net10.0/osx-arm64/publish/CrestCore.Native.dylib"
[[ -f "$core_library" ]]

print "Building CrestChromiumUIProduct (Release, build $build_number)..."
xcodebuild build \
  -quiet \
  -project Crest.xcodeproj \
  -scheme CrestChromiumUIProduct \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO
ui_framework="$derived_data_path/Build/Products/Release/CrestChromiumUIProduct.framework"
[[ -d "$ui_framework" ]]
for entry in crest_chromium_ui_start crest_native_host_run; do
  nm -gU "$ui_framework/CrestChromiumUIProduct" | grep -q "_${entry}\$" \
    || { print -u2 "CrestChromiumUIProduct does not export $entry."; exit 1; }
done

# Only entitlements that need no provisioning profile. The packager adds
# Chromium's own device entitlements on top.
entitlements="$work_root/entitlements.plist"
cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.device.camera</key>
	<true/>
	<key>com.apple.security.personal-information.location</key>
	<true/>
</dict>
</plist>
PLIST

rm -rf "$output_path"
mkdir -p "${output_path:h}"
CREST_DEFAULT_UPDATE_CHANNEL=development python3 Scripts/control-plane/package-chromium-host.py \
  --browser "$engine_path" \
  --product \
  --distribution \
  --ui "$ui_framework" \
  --core "$core_library" \
  --entitlements "$entitlements" \
  --signing-identity "$signing_identity_hash" \
  --output "$output_path"

codesign --verify --deep --strict "$output_path"
[[ "$(defaults read "$output_path/Contents/Info" CFBundleIdentifier)" == "com.pauldavis.crest" ]]
"$lsregister" -u "$output_path" >/dev/null 2>&1 || true
print "Built $output_path ($(defaults read "$output_path/Contents/Info" CFBundleShortVersionString), build $build_number)."

[[ "$install" == true ]] || { print "Run again with --install to back up your data and install it."; exit 0; }

# --- Quit Crest ---
installed_crest_pattern="^${application_path}/Contents/MacOS/"
if pgrep -f "$installed_crest_pattern" >/dev/null 2>&1; then
  print "Quitting Crest..."
  osascript -e 'tell application "Crest" to quit'
  for _ in {1..300}; do
    pgrep -f "$installed_crest_pattern" >/dev/null 2>&1 || break
    sleep 0.1
  done
fi
if pgrep -f "$installed_crest_pattern" >/dev/null 2>&1; then
  print -u2 "Crest did not quit; nothing was replaced."
  exit 1
fi

# --- Back up data and the current app ---
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$backup_root/$stamp"
mkdir -p "$backup"
print "Backing up data to $backup..."
ditto "$HOME/Library/Application Support/Crest" "$backup/Application Support/Crest"
[[ -f "$HOME/Library/Preferences/com.pauldavis.crest.plist" ]] \
  && cp -p "$HOME/Library/Preferences/com.pauldavis.crest.plist" "$backup/"
if [[ -d "$application_path" ]]; then
  ditto "$application_path" "$backup/Crest.app"
  "$lsregister" -u "$backup/Crest.app" >/dev/null 2>&1 || true
fi
# Keep the three newest backups.
ls -1d "$backup_root"/*(/N) | sort -r | tail -n +4 | while read -r old; do rm -rf "$old"; done

# --- Install ---
staging="/Applications/.Crest-personal-install-$$.app"
ditto "$output_path" "$staging"
codesign --verify --deep --strict "$staging"
rm -rf "$application_path"
mv "$staging" "$application_path"
"$lsregister" -f "$application_path" >/dev/null 2>&1 || true
open "$application_path"
print "Installed. Backup of your data and the previous app: $backup"
