#!/bin/zsh
# Builds the AppMix menu bar app and wraps it in dist/AppMix.app so macOS asks for audio-capture
# permission in AppMix's own name. With --install, also replaces ~/Applications/AppMix.app, the
# stable copy that launch at login points to. Prints the path of the bundle to run.
set -euo pipefail

root="${0:A:h:h}"
bundle="$root/dist/AppMix.app"
installed="$HOME/Applications/AppMix.app"

swift build -c release --package-path "$root" >&2
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$root/.build/release/AppMixBar" "$bundle/Contents/MacOS/AppMixBar"
cp "$root/scripts/Info.plist" "$bundle/Contents/Info.plist"
# VERSION at the repo root is the one source of the app's version.
plutil -replace CFBundleShortVersionString -string "$(tr -d '[:space:]' < "$root/VERSION")" "$bundle/Contents/Info.plist"
# Ad-hoc signature: enough for permission prompts on this Mac. Each rebuild may ask again.
codesign --force --sign - "$bundle" >&2

if [[ "${1:-}" == "--install" ]]; then
  pkill -x AppMixBar || true
  mkdir -p "$HOME/Applications"
  rm -rf "$installed"
  ditto "$bundle" "$installed"
  echo "$installed"
else
  echo "$bundle"
fi
