#!/bin/bash
set -euo pipefail
umask 077

[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REF_TYPE:-}" == tag ]] || { echo 'Run this script from the tag release workflow.' >&2; exit 1; }
source "$(dirname "${BASH_SOURCE[0]}")/release.conf"
# Every release tag must have an increasing version for Sparkle updates.
BUILD_NUMBER="$RELEASE_VERSION"
for name in RELEASE_VERSION BUILD_NUMBER RELEASE_REPOSITORY APPLE_TEAM_ID DEVELOPER_ID_APPLICATION \
  DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD APPLE_API_KEY_P8_BASE64 \
  APPLE_API_KEY_ID APPLE_API_ISSUER_ID SPARKLE_PRIVATE_ED_KEY SPARKLE_PUBLIC_ED_KEY; do
  [[ -n "${!name:-}" ]] || {
    echo "Missing release setting: $name. Set public values in scripts/release.conf, signing identity and credentials in Actions secrets." >&2
    exit 1
  }
done
[[ "$DEVELOPER_ID_APPLICATION" == 'Developer ID Application: '* ]]
printf '%s' "$SPARKLE_PUBLIC_ED_KEY" | base64 --decode | wc -c | xargs test 32 -eq
jq -e --arg version "$SPARKLE_VERSION" '.pins[] | select(.identity == "sparkle") | .state.version == $version' \
  apps/macOS/Launchpod.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved >/dev/null

work="$RUNNER_TEMP/launchpod-release"
mkdir -p "$work/private" "$work/updates" "$work/public"
keychain="$work/private/signing.keychain-db"
password="$(openssl rand -hex 32)"
original_keychains=()
while IFS= read -r value; do original_keychains+=("$(echo "$value" | sed 's/^[[:space:]]*"//;s/"$//')"); done < <(security list-keychains -d user)
cleanup() {
  security list-keychains -d user -s "${original_keychains[@]}" || true
  security delete-keychain "$keychain" 2>/dev/null || true
  rm -rf "$work/private"
}
trap cleanup EXIT
printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" | base64 --decode > "$work/private/certificate.p12"
printf '%s' "$APPLE_API_KEY_P8_BASE64" | base64 --decode > "$work/private/notary.p8"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" > "$work/private/sparkle.key"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$work/private/certificate.p12" -k "$keychain" -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"

feed="$GITHUB_RELEASES_URL/latest/download/appcast.xml"
marketing_version="$(plutil -convert json -o - apps/macOS/Launchpod.xcodeproj/project.pbxproj | jq -er '
  .objects as $objects | $objects[] | select(.isa == "PBXNativeTarget" and .name == "Launchpod") |
  $objects[.buildConfigurationList].buildConfigurations[] | $objects[.] |
  select(.name == "Release") | .buildSettings.MARKETING_VERSION')"
xcodebuild -version
xcodebuild archive -project apps/macOS/Launchpod.xcodeproj -scheme Launchpod -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$work/Launchpod.xcarchive" \
  -derivedDataPath "$work/DerivedData" -clonedSourcePackagesDirPath "$work/Packages" \
  -onlyUsePackageVersionsFromResolvedFile ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=26.0 CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --keychain $keychain" \
  LAUNCHPOD_UPDATE_FEED_URL="$feed" LAUNCHPOD_UPDATE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY"
jq -n --arg team "$APPLE_TEAM_ID" --arg certificate "$DEVELOPER_ID_APPLICATION" \
  '{method:"developer-id",signingStyle:"manual",teamID:$team,signingCertificate:$certificate}' > "$work/export.json"
plutil -convert xml1 -o "$work/ExportOptions.plist" "$work/export.json"
xcodebuild -exportArchive -archivePath "$work/Launchpod.xcarchive" -exportPath "$work/export" -exportOptionsPlist "$work/ExportOptions.plist"
app="$work/export/Launchpod.app"
info="$app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$info")" == "$marketing_version" ]]
[[ "$(plutil -extract CFBundleVersion raw "$info")" == "$BUILD_NUMBER" ]]
[[ "$(plutil -extract SUFeedURL raw "$info")" == "$feed" ]]
[[ "$(plutil -extract SUPublicEDKey raw "$info")" == "$SPARKLE_PUBLIC_ED_KEY" ]]
[[ "$(plutil -extract SURequireSignedFeed raw "$info")" == true ]]
[[ "$(plutil -extract SUVerifyUpdateBeforeExtraction raw "$info")" == true ]]
[[ -d "$app/Contents/PlugIns/LaunchpodDockTile.docktileplugin" && -d "$app/Contents/Frameworks/Sparkle.framework" ]]
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    lipo "$binary" -verify_arch arm64
    lipo "$binary" -verify_arch x86_64
    codesign -dv --verbose=4 "$binary" 2>&1 | grep -Fq "TeamIdentifier=$APPLE_TEAM_ID"
  fi
done < <(find "$app" -type f -print0)
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv --verbose=4 "$app" 2>&1 | grep -q 'flags=.*runtime'

notarize() {
  xcrun notarytool submit "$1" --key "$work/private/notary.p8" --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" --wait --timeout 30m --output-format json > "$work/notary.json"
  xcrun notarytool log "$(jq -r .id "$work/notary.json")" --key "$work/private/notary.p8" \
    --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" "$work/notary-log.json"
  jq -e '.status == "Accepted"' "$work/notary.json" >/dev/null
  jq '.issues // []' "$work/notary-log.json"
}
ditto -c -k --keepParent --sequesterRsrc "$app" "$work/notarization.zip"
notarize "$work/notarization.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
mkdir "$work/dmg-content"
ditto "$app" "$work/dmg-content/Launchpod.app"
dmg_name="Launchpod-${RELEASE_VERSION}-universal.dmg"
dmg="$work/updates/$dmg_name"
command -v create-dmg >/dev/null || brew install create-dmg
sips -s format png scripts/dmg-background.svg --out "$work/dmg-background.png" >/dev/null
create-dmg --volname Launchpod --filesystem APFS --format ULFO \
  --window-pos 200 120 --window-size 600 400 --icon-size 100 \
  --icon Launchpod.app 150 190 --hide-extension Launchpod.app --app-drop-link 450 190 \
  --background "$work/dmg-background.png" "$dmg" "$work/dmg-content"
codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp --keychain "$keychain" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
hdiutil verify "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

# Use the tools from the same Sparkle release as Package.resolved.
curl --fail --location --retry 3 --proto '=https' "$SPARKLE_TOOLS_URL" -o "$work/Sparkle.tar.xz"
printf '%s  %s\n' "$SPARKLE_TOOLS_SHA256" "$work/Sparkle.tar.xz" | shasum -a 256 -c -
mkdir "$work/sparkle"
tar -xJf "$work/Sparkle.tar.xz" -C "$work/sparkle"
cp "$work/RELEASE_NOTES.md" "$work/updates/${dmg_name%.dmg}.md"
"$work/sparkle/bin/generate_appcast" --ed-key-file "$work/private/sparkle.key" --maximum-deltas 0 \
  --download-url-prefix "$GITHUB_RELEASES_URL/download/$GITHUB_REF_NAME/" \
  --embed-release-notes "$work/updates"
appcast="$work/updates/appcast.xml"
signature="$(xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$appcast")"
[[ -n "$signature" ]]
"$work/sparkle/bin/sign_update" --ed-key-file "$work/private/sparkle.key" --verify "$dmg" "$signature"
"$work/sparkle/bin/sign_update" --ed-key-file "$work/private/sparkle.key" --verify "$appcast"
cp "$dmg" "$appcast" "$work/public/"
(cd "$work/public" && shasum -a 256 "$dmg_name" appcast.xml > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
