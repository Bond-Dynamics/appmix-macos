#!/bin/zsh
# Builds the Sparkle update for a finished (signed, notarized, stapled) AppMix.app (BOND-224):
#   dist/AppMix-<version>.zip   the update archive Sparkle downloads
#   dist/appcast.xml            the feed, one item, served as a release asset at releases/latest/download/
#
#   make-appcast.sh <path/to/AppMix.app>
#
# Env:
#   SPARKLE_ED_PRIVATE_KEY  the EdDSA private key (CI). Unset: sign_update uses the "appmix" key in the
#                           login Keychain (local builds). Passed on stdin, never on the command line.
#   DOWNLOAD_BASE           where the zip will live (default: this version's GitHub release download URL)
set -euo pipefail

root="${0:A:h:h:h}"
repo_url="https://github.com/Bond-Dynamics/appmix-macos"
app="${1:?usage: make-appcast.sh <path/to/AppMix.app>}"
plist="$app/Contents/Info.plist"
[[ -f "$plist" ]] || { echo "make-appcast.sh: $app is not an app bundle" >&2; exit 64; }

# The feed describes the artifact, so its numbers come from the artifact rather than from VERSION.
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")"
expected="$("$root/scripts/release/build-number.sh" "$version")"
[[ "$build" == "$expected" ]] || { echo "make-appcast.sh: build $build does not match $version (want $expected)" >&2; exit 1; }

sign_update="$(find "$root/.build/artifacts" -path '*/Sparkle/bin/sign_update' -type f 2>/dev/null | head -1 || true)"
[[ -x "$sign_update" ]] || { echo "make-appcast.sh: sign_update not found; run 'swift package resolve' first" >&2; exit 1; }

tag="v$version"
download_base="${DOWNLOAD_BASE:-$repo_url/releases/download/$tag}"
zip="$root/dist/AppMix-$version.zip"
appcast="$root/dist/appcast.xml"

rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

# Prints `sparkle:edSignature="…" length="…"`, the two enclosure attributes the feed needs.
sign() {
  if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$@"
  else
    "$sign_update" --account appmix "$@"
  fi
}
attributes="$(sign "$zip")"
[[ "$attributes" == sparkle:edSignature=*length=* ]] || { echo "make-appcast.sh: unexpected sign_update output" >&2; exit 1; }
signature="${${attributes#*edSignature=\"}%%\"*}"
# Checked against the public key inside the app being shipped, as installed copies will check it. Verifying
# with the signing key itself could not catch a CI secret that isn't the private half of that key.
swift "$root/scripts/release/verify-update.swift" "$zip" "$signature" "$public_key" >&2

cat > "$appcast" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>AppMix</title>
    <link>$repo_url</link>
    <item>
      <title>AppMix $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$repo_url/releases/tag/$tag</sparkle:fullReleaseNotesLink>
      <enclosure url="$download_base/${zip:t}" $attributes type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$appcast"

echo "Update $version (build $build): ${zip:t}, ${appcast:t}" >&2
echo "$appcast"
