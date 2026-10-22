#!/bin/zsh
# Builds dist/AppMix-<VERSION>.dmg: universal app, drag-to-Applications window, and (unless
# --skip-notarize) Developer ID signing + notarization + stapling of both the app and the DMG.
#
# Env:
#   SIGN_IDENTITY        "Developer ID Application: ..." (required to notarize; default "-" = ad-hoc)
#   Notarization credentials, one of:
#   NOTARY_PROFILE       a keychain profile saved with `xcrun notarytool store-credentials` (local builds)
#   ASC_KEY_PATH         App Store Connect API key file (AuthKey_<id>.p8) (CI)
#   ASC_KEY_ID           its key id
#   ASC_ISSUER_ID        its issuer id
#   DMGBUILD             dmgbuild command, may be several words (default: dmgbuild; CI: python3 -m dmgbuild, pinned 1.6.5)
set -euo pipefail

root="${0:A:h:h:h}"
version="$(tr -d '[:space:]' < "$root/VERSION")"
dmg="$root/dist/AppMix-$version.dmg"
dmgbuild="${DMGBUILD:-dmgbuild}"
notarize=true
[[ "${1:-}" == "--skip-notarize" ]] && notarize=false

notary_auth=()
if $notarize; then
  required=(SIGN_IDENTITY)
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary_auth=(--keychain-profile "$NOTARY_PROFILE")
  else
    required+=(ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID)
  fi
  for var in $required; do
    [[ -n "${(P)var:-}" && "${(P)var}" != "-" ]] || { echo "package-dmg.sh: $var is required to notarize (or set NOTARY_PROFILE, or pass --skip-notarize)" >&2; exit 64; }
  done
  (( ${#notary_auth} )) || notary_auth=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
fi

# Submits a file to Apple's notary service, waits, and fails with Apple's log if not accepted.
notarize_file() {
  local file="$1" result status id
  result="$(xcrun notarytool submit "$file" "${notary_auth[@]}" --wait --timeout 30m --output-format json)"
  status="$(plutil -extract status raw - <<< "$result")"
  id="$(plutil -extract id raw - <<< "$result")"
  echo "Notarization of ${file:t}: $status (submission $id)" >&2
  if [[ "$status" != "Accepted" ]]; then
    xcrun notarytool log "$id" "${notary_auth[@]}" >&2 || true
    exit 1
  fi
}

app="$("$root/scripts/make-app.sh" --universal)"
echo "Built $(lipo -archs "$app/Contents/MacOS/AppMixBar") app: $app" >&2

if $notarize; then
  zip="$root/dist/AppMix-$version-notarize.zip"
  ditto -c -k --keepParent "$app" "$zip"
  notarize_file "$zip"
  rm -f "$zip"
  xcrun stapler staple "$app" >&2
fi

rm -f "$dmg"
${=dmgbuild} -s "$root/scripts/dmg/settings.py" \
  -D app="$app" -D background="$root/scripts/dmg/background.tiff" -D icon="$root/Resources/AppIcon.icns" \
  "AppMix" "$dmg" >&2

if $notarize; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg" >&2
  notarize_file "$dmg"
  xcrun stapler staple "$dmg" >&2
  xcrun stapler validate "$dmg" >&2
  spctl -a -t open --context context:primary-signature -vv "$dmg" >&2
fi

echo "$dmg"
