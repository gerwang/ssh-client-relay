#!/usr/bin/env bash
set -euo pipefail

: "${TEST_ARGS:?TEST_ARGS is required}"
printf '%s\n' "$@" >"$TEST_ARGS"
