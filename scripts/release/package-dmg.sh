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
  local file="$1" result verdict id
  result="$(xcrun notarytool submit "$file" "${notary_auth[@]}" --wait --timeout 30m --output-format json)"
  verdict="$(plutil -extract status raw - <<< "$result")"
  id="$(plutil -extract id raw - <<< "$result")"
  echo "Notarization of ${file:t}: $verdict (submission $id)" >&2
  if [[ "$verdict" != "Accepted" ]]; then
    xcrun notarytool log "$id" "${notary_auth[@]}" >&2 || true
    exit 1
  fi
}

# Attaches Apple's notarization ticket. `stapler` fetches it from api.apple-cloudkit.com, which drops
# connections intermittently from GitHub's macOS runners (NSURLError -1005, three runs in BOND-220), so
# retry with backoff. Re-stapling an already stapled file is harmless.
staple_with_retry() {
  local file="$1" attempt
  for attempt in 1 2 3 4 5; do
    xcrun stapler staple "$file" >&2 && return 0
    echo "stapler attempt $attempt for ${file:t} failed; retrying" >&2
    sleep $(( attempt * 10 ))
  done
  echo "package-dmg.sh: could not staple ${file:t} after 5 attempts" >&2
  exit 1
}

# Gatekeeper's verdict on the finished DMG, as a downloading Mac would see it. Retries a network failure.
assess_dmg() {
  local file="$1" attempt
  for attempt in 1 2 3; do
    spctl -a -t open --context context:primary-signature -vv "$file" >&2 && return 0
    echo "spctl assessment attempt $attempt failed; retrying" >&2
    sleep $(( attempt * 10 ))
  done
  echo "package-dmg.sh: Gatekeeper rejected ${file:t}" >&2
  exit 1
}

app="$("$root/scripts/make-app.sh" --universal)"
echo "Built $(lipo -archs "$app/Contents/MacOS/AppMixBar") app: $app" >&2

if $notarize; then
  zip="$root/dist/AppMix-$version-notarize.zip"
  ditto -c -k --keepParent "$app" "$zip"
  notarize_file "$zip"
  rm -f "$zip"
  staple_with_retry "$app"
fi

rm -f "$dmg"
${=dmgbuild} -s "$root/scripts/dmg/settings.py" \
  -D app="$app" -D background="$root/scripts/dmg/background.tiff" -D icon="$root/Resources/AppIcon.icns" \
  "AppMix" "$dmg" >&2

if $notarize; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg" >&2
  notarize_file "$dmg"
  staple_with_retry "$dmg"
  # `stapler staple` already validates the ticket it attaches. A separate `stapler validate` looks the
  # ticket up online and failed twice on GitHub's macOS runner with NSURLError -1005 (BOND-220), so the
  # final gate is Gatekeeper's own assessment, retried briefly in case the runner's network blips.
  assess_dmg "$dmg"
fi

echo "$dmg"
