#!/usr/bin/env bash
set -euo pipefail

: "${TEST_ARGS:?TEST_ARGS is required}"
: "${TEST_STDIN:?TEST_STDIN is required}"

printf '%s\n' "$@" >"$TEST_ARGS"
cat >"$TEST_STDIN"
printf '%s' "${TEST_STDOUT:-fake-ssh-output}"
