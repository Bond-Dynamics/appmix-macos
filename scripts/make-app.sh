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

# The rpath lets the binary find Sparkle in Contents/Frameworks. Set at link time: patching it in later
# with install_name_tool depends on spare header space the linker doesn't promise.
build_args=(-c release --package-path "$root" --product AppMixBar -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
$universal && build_args+=(--arch arm64 --arch x86_64)
swift build "${build_args[@]}" >&2
binary="$(swift build "${build_args[@]}" --show-bin-path)/AppMixBar"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
cp "$binary" "$bundle/Contents/MacOS/AppMixBar"
# Sparkle (BOND-224) sits next to the built binary. Its XPC services exist only for sandboxed apps,
# and AppMix is not sandboxed, so they are dropped rather than signed and shipped.
sparkle="$bundle/Contents/Frameworks/Sparkle.framework"
ditto "${binary:h}/Sparkle.framework" "$sparkle"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
# Sparkle is MIT-licensed, which asks for its notice to travel with the copy.
cp "$(find "$root/.build/artifacts" -path '*/Sparkle/LICENSE' -type f | head -1)" "$bundle/Contents/Resources/Sparkle-LICENSE"
cp "$root/scripts/Info.plist" "$bundle/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
# VERSION at the repo root is the one source of the app's version.
plutil -replace CFBundleShortVersionString -string "$(tr -d '[:space:]' < "$root/VERSION")" "$bundle/Contents/Info.plist"
# Sparkle offers an update only when the feed's build number is higher than this one.
plutil -replace CFBundleVersion -string "$("$root/scripts/release/build-number.sh")" "$bundle/Contents/Info.plist"
# An ad-hoc dev build must not offer itself the published release, so it gets no feed and no updater.
[[ "$identity" == "-" ]] && plutil -remove SUFeedURL "$bundle/Contents/Info.plist"

# Inside out: Sparkle's helpers, then the framework, then the app. `--deep` would sign them all
# with the app's flags and is not what Apple recommends.
if [[ "$identity" == "-" ]]; then
  sign=(codesign --force --sign -)
else
  sign=(codesign --force --options runtime --timestamp --sign "$identity")
fi
"${sign[@]}" "$sparkle/Versions/B/Autoupdate" >&2
"${sign[@]}" "$sparkle/Versions/B/Updater.app" >&2
"${sign[@]}" "$sparkle" >&2
"${sign[@]}" "$bundle" >&2

if $install; then
  pkill -x AppMixBar || true
  mkdir -p "$HOME/Applications"
  rm -rf "$installed"
  ditto "$bundle" "$installed"
  echo "$installed"
else
  echo "$bundle"
fi
