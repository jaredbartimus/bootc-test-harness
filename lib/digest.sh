#!/usr/bin/env bash
#
# lib/digest.sh - Resolve immutable base image digest using skopeo
#

set -euo pipefail

# Resolves base image reference to an immutable digest reference.
# Sets globals:
#   BASE_IMAGE_REQUESTED
#   BASE_IMAGE_RESOLVED
resolve_base_image() {
  local ref="$1"
  BASE_IMAGE_REQUESTED="$ref"

  # Case 1: Already pinned by digest (e.g. image@sha256:...)
  if [[ "$ref" == *"@"* ]]; then
    BASE_IMAGE_RESOLVED="$ref"
    log_info "Base image is already an immutable digest reference."
    log_info "  Requested base reference : ${BASE_IMAGE_REQUESTED}"
    log_info "  Immutable base reference : ${BASE_IMAGE_RESOLVED}"
    return 0
  fi

  # Case 2: Mutable/tagged reference (e.g. image:tag or image)
  log_info "Resolving immutable digest for base tag: ${ref}"

  local inspect_out
  if ! inspect_out="$(skopeo inspect "docker://${ref}" 2>&1)"; then
    die "Failed to inspect remote image 'docker://${ref}' via skopeo:\n${inspect_out}"
  fi

  local digest
  digest="$(echo "${inspect_out}" | jq -r '.Digest // empty')"
  if [ -z "${digest}" ] || [ "${digest}" = "null" ]; then
    die "Failed to extract digest from skopeo inspect for '${ref}'"
  fi

  # Strip tag from reference if present, preserving registry port and path
  local last_part="${ref##*/}"
  local repo_without_tag
  if [[ "$last_part" == *":"* ]]; then
    local repo_path="${ref%/*}"
    local image_name="${last_part%%:*}"
    if [ "$repo_path" = "$ref" ]; then
      repo_without_tag="${image_name}"
    else
      repo_without_tag="${repo_path}/${image_name}"
    fi
  else
    repo_without_tag="${ref}"
  fi

  BASE_IMAGE_RESOLVED="${repo_without_tag}@${digest}"

  log_info "Base image digest resolved successfully:"
  log_info "  Requested base reference : ${BASE_IMAGE_REQUESTED}"
  log_info "  Immutable base reference : ${BASE_IMAGE_RESOLVED}"
}
