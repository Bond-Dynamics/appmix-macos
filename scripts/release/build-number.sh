#!/bin/zsh
# Prints the integer CFBundleVersion for a semver: major*10000 + minor*100 + patch (0.5.0 -> 500).
# Sparkle offers an update only when the feed's build number is higher than the running app's, so it
# must grow with every release. Pre-release versions (0.6.0-beta.1) are refused: they would share the final
# release's number, and the feed has no beta channel to keep them from everyone. Reads VERSION with no argument.
set -euo pipefail

version="${1-$(tr -d '[:space:]' < "${0:A:h:h:h}/VERSION")}"
if [[ ! "$version" =~ '^([0-9]+)\.([0-9]+)\.([0-9]+)$' ]]; then
  echo "build-number.sh: '$version' is not a release version like 0.5.0 (no pre-release suffix)" >&2
  exit 64
fi
major=$match[1] minor=$match[2] patch=$match[3]
if (( minor >= 100 || patch >= 100 )); then
  echo "build-number.sh: minor and patch must stay below 100 to fit the build number ($version)" >&2
  exit 64
fi
echo $(( 10#$major * 10000 + 10#$minor * 100 + 10#$patch ))
