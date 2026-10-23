#!/bin/zsh
# Checks build-number.sh, which turns VERSION into the integer CFBundleVersion Sparkle compares (BOND-224).
set -uo pipefail

script="${0:A:h}/build-number.sh"
failures=0

expect() {
  local input="$1" want="$2" got
  got="$("$script" "$input" 2>/dev/null)"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $input -> '$got', want '$want'" >&2
    (( failures++ ))
  fi
}

expect_rejected() {
  local input="$1"
  if "$script" "$input" >/dev/null 2>&1; then
    echo "FAIL: $input was accepted" >&2
    (( failures++ ))
  fi
}

expect 0.5.0 500
expect 0.4.0 400
expect 1.2.3 10203
expect 12.99.99 129999
# A pre-release would share its final release's number and, published as a normal release, reach everyone.
expect_rejected 0.6.0-beta.1
expect_rejected 0.100.0
expect_rejected 0.5.100
expect_rejected 0.5
expect_rejected v0.5.0
expect_rejected ""

# With no argument it reads VERSION at the repo root.
want="$("$script" "$(tr -d '[:space:]' < "${0:A:h:h:h}/VERSION")")"
[[ "$("$script")" == "$want" ]] || { echo "FAIL: no-argument form did not read VERSION" >&2; (( failures++ )); }

(( failures == 0 )) && echo "build-number: all checks passed"
exit $(( failures > 0 ))
