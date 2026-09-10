#!/usr/bin/env bash
#
# tests/fixtures/test-smoke.sh - Lightweight validation script for integration test
#
set -euo pipefail

workdir="${1:-/tmp/work}"
echo "::: [test-smoke] Running in workdir: ${workdir}"

# 1. Verify caller arguments passed
if [ -z "${workdir}" ]; then
  echo "FAIL: Expected workdir argument" >&2
  exit 1
fi

# 2. If a second argument is passed, verify it preserved spaces and metacharacters literally
if [ "$#" -ge 2 ]; then
  arg2="$2"
  # shellcheck disable=SC2016
  expected='argument "with" $dollar ; semicolon'
  if [ "${arg2}" != "${expected}" ]; then
    echo "FAIL: Expected arg2 to be literally: ${expected}" >&2
    echo "      Actual arg2 received:         ${arg2}" >&2
    echo "Total arguments received: $#" >&2
    for i in "$@"; do
      echo "  arg: '${i}'" >&2
    done
    exit 1
  fi
  echo "  ok   verified literal argv element with shell metacharacters: '${arg2}'"
fi

# 3. Verify installed package file
if [ ! -f /etc/dummy-test.conf ]; then
  echo "FAIL: /etc/dummy-test.conf missing" >&2
  exit 1
fi

content="$(cat /etc/dummy-test.conf)"
if [ "${content}" != "dummy-test-installed" ]; then
  echo "FAIL: Unexpected content in /etc/dummy-test.conf: ${content}" >&2
  exit 1
fi

echo "  ok   /etc/dummy-test.conf verified"
echo "::: [test-smoke] Smoke validation passed successfully."
