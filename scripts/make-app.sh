#!/bin/zsh
# Builds the AppMix menu bar app and wraps it in dist/AppMix.app so macOS asks for audio-capture
# permission in AppMix's own name. Prints the path of the bundle to run.
#
#   --universal   build for Apple Silicon and Intel (release builds for distribution)
#   --install     also replace ~/Applications/AppMix.app, the stable copy launch at login points to
#
# SIGN_IDENTITY (env) picks the signature. Default "-" is ad-hoc: fine on this Mac, but each rebuild
# re-asks for audio permission. A real identity ("Developer ID Application: ...") signs with the
# hardened runtime and a secure timestamp, which notarization requires.
set -euo pipefail

root="${0:A:h:h}"
bundle="$root/dist/AppMix.app"
installed="$HOME/Applications/AppMix.app"
identity="${SIGN_IDENTITY:--}"
universal=false
install=false
for arg in "$@"; do
  case "$arg" in
    --universal) universal=true ;;
    --install) install=true ;;
    *) echo "make-app.sh: unknown option '$arg'" >&2; exit 64 ;;
  esac
done

build_args=(-c release --package-path "$root" --product AppMixBar)
$universal && build_args+=(--arch arm64 --arch x86_64)
swift build "${build_args[@]}" >&2
binary="$(swift build "${build_args[@]}" --show-bin-path)/AppMixBar"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary" "$bundle/Contents/MacOS/AppMixBar"
cp "$root/scripts/Info.plist" "$bundle/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
# VERSION at the repo root is the one source of the app's version.
plutil -replace CFBundleShortVersionString -string "$(tr -d '[:space:]' < "$root/VERSION")" "$bundle/Contents/Info.plist"

if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$bundle" >&2
else
  codesign --force --options runtime --timestamp --sign "$identity" "$bundle" >&2
fi

if $install; then
  pkill -x AppMixBar || true
  mkdir -p "$HOME/Applications"
  rm -rf "$installed"
  ditto "$bundle" "$installed"
  echo "$installed"
else
  echo "$bundle"
fi
