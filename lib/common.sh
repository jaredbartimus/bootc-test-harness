#!/usr/bin/env bash
#
# lib/common.sh - Shared utility functions for bootc-test-harness
#

set -euo pipefail

log_info() {
  echo "::: [bootc-test] $*"
}

log_warn() {
  echo "WARN: [bootc-test] $*" >&2
}

log_error() {
  echo "ERROR: [bootc-test] $*" >&2
}

die() {
  log_error "$@"
  exit 1
}

check_prerequisites() {
  local missing=()
  local tool
  for tool in podman skopeo jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    die "Missing required host tools: ${missing[*]}. Please install them before running bootc-test."
  fi
}

export_provenance() {
  local requested_base="$1"
  local resolved_base="$2"
  local derived_tag="$3"
  local derived_id="${4:-none}"

  echo ""
  echo "============================================================"
  echo "                bootc-test Provenance Summary                "
  echo "============================================================"
  echo "  Requested Base Image : ${requested_base}"
  echo "  Resolved Base Image  : ${resolved_base}"
  echo "  Derived Image Tag    : ${derived_tag}"
  echo "  Derived Image ID     : ${derived_id}"
  echo "============================================================"
  echo ""

  if [ -n "${GITHUB_OUTPUT:-}" ] && [ -w "${GITHUB_OUTPUT}" ]; then
    {
      echo "base_image_requested=${requested_base}"
      echo "base_image_resolved=${resolved_base}"
      echo "derived_image_tag=${derived_tag}"
      echo "derived_image_id=${derived_id}"
    } >> "${GITHUB_OUTPUT}"
  fi
}
