#!/usr/bin/env bash
#
# lib/build.sh - Assemble build context, generate Containerfile, and run podman build
#

set -euo pipefail

BUILD_CONTEXT_DIR=""
CREATED_IMAGE_ID=""

# Setup exit trap for cleanup of context and disposable images
# shellcheck disable=SC2317
cleanup() {
  if [ -n "${BUILD_CONTEXT_DIR:-}" ] && [ -d "${BUILD_CONTEXT_DIR}" ]; then
    log_info "Cleaning up temporary build context: ${BUILD_CONTEXT_DIR}"
    rm -rf "${BUILD_CONTEXT_DIR}"
  fi

  if [ "${KEEP_IMAGE:-false}" = "true" ]; then
    if [ -n "${CREATED_IMAGE_ID:-}" ]; then
      log_info "Preserving derived image as requested (--keep-image): ${DERIVED_TAG} (${CREATED_IMAGE_ID})"
    fi
    return 0
  fi

  # Ownership-safe image cleanup
  # Because tag collisions are rejected before build, any image tagged with DERIVED_TAG
  # was created exclusively by this invocation.
  if [ -n "${CREATED_IMAGE_ID:-}" ]; then
    log_info "Removing disposable derived test image: ${DERIVED_TAG}"
    podman rmi -f "${DERIVED_TAG}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Assembles build context and executes derived bootc container build and validation.
# Globals read:
#   BASE_IMAGE_RESOLVED
#   RPMS_DIR
#   TEST_SCRIPT
#   TEST_ARGS (array)
#   DERIVED_TAG
#   CALLER_TAG_SPECIFIED (boolean)
#   KEEP_IMAGE (boolean)
# Globals set:
#   DERIVED_IMAGE_TAG
#   DERIVED_IMAGE_ID
run_build_and_validation() {
  BUILD_CONTEXT_DIR="$(mktemp -d -t bootc-test-context.XXXXXX)"

  # 1. Verify caller RPMs
  [ -d "${RPMS_DIR}" ] || die "RPM directory not found: ${RPMS_DIR}"

  shopt -s nullglob
  local rpm_files=("${RPMS_DIR}"/*.rpm)
  shopt -u nullglob

  if [ "${#rpm_files[@]}" -eq 0 ]; then
    die "No .rpm files found in directory: ${RPMS_DIR}"
  fi

  log_info "Staging ${#rpm_files[@]} caller RPM(s) from ${RPMS_DIR} into build context..."
  mkdir -p "${BUILD_CONTEXT_DIR}/rpms"
  cp -L "${rpm_files[@]}" "${BUILD_CONTEXT_DIR}/rpms/"

  # 2. Stage test script if provided
  local has_test_script=false
  if [ -n "${TEST_SCRIPT:-}" ]; then
    [ -f "${TEST_SCRIPT}" ] || die "Test script not found: ${TEST_SCRIPT}"
    has_test_script=true
    mkdir -p "${BUILD_CONTEXT_DIR}/test-assets"
    cp "${TEST_SCRIPT}" "${BUILD_CONTEXT_DIR}/test-assets/test-script"
    chmod +x "${BUILD_CONTEXT_DIR}/test-assets/test-script"

    # Generate runner script with argv-safe passthrough
    {
      echo '#!/usr/bin/env bash'
      echo 'set -euo pipefail'
      echo 'args=()'
      for arg in "${TEST_ARGS[@]}"; do
        printf 'args+=(%q)\n' "${arg}"
      done
      cat <<'RUNNER_EXEC'
if [ -x /tmp/test-assets/test-script ]; then
  exec /tmp/test-assets/test-script "${args[@]}"
else
  exec /bin/bash /tmp/test-assets/test-script "${args[@]}"
fi
RUNNER_EXEC
    } > "${BUILD_CONTEXT_DIR}/test-assets/run-test.sh"
    chmod +x "${BUILD_CONTEXT_DIR}/test-assets/run-test.sh"
    log_info "Staged caller test script: ${TEST_SCRIPT} with ${#TEST_ARGS[@]} argument(s)"
  fi

  # 3. Generate Containerfile
  {
    cat <<'DOCKERFILE_HEAD'
ARG BASE_IMAGE

FROM scratch AS ctx
COPY rpms /rpms
DOCKERFILE_HEAD

    if [ "${has_test_script}" = "true" ]; then
      echo 'COPY test-assets /test-assets'
    fi

    cat <<'DOCKERFILE_BASE'

FROM ${BASE_IMAGE}

# Install caller RPMs using ephemeral bind and cache/tmpfs mounts
RUN --mount=type=bind,from=ctx,source=/rpms,target=/tmp/rpms,ro \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/run \
    --mount=type=tmpfs,dst=/tmp \
    dnf5 install -y /tmp/rpms/*.rpm

DOCKERFILE_BASE

    if [ "${has_test_script}" = "true" ]; then
      cat <<'DOCKERFILE_TEST'
# Execute caller validation script inside tmpfs work environment
RUN --mount=type=bind,from=ctx,source=/test-assets,target=/tmp/test-assets,ro \
    --mount=type=tmpfs,target=/tmp/work \
    /bin/bash /tmp/test-assets/run-test.sh

DOCKERFILE_TEST
    fi

    cat <<'DOCKERFILE_LINT'
# Mandatory static structural bootc validation
RUN bootc container lint
DOCKERFILE_LINT
  } > "${BUILD_CONTEXT_DIR}/Containerfile"

  # 4. Enforce ownership safety: reject pre-existing tags before building
  local tag_exists=false
  if podman image exists "${DERIVED_TAG}" 2>/dev/null || [ -n "$(podman images -q "${DERIVED_TAG}" 2>/dev/null || true)" ]; then
    tag_exists=true
  fi

  if [ "${tag_exists}" = "true" ]; then
    if [ "${CALLER_TAG_SPECIFIED}" = "true" ]; then
      die "Image tag '${DERIVED_TAG}' already exists. Refusing to overwrite pre-existing image tag."
    else
      # Re-generate harness-owned tag if unexpected collision occurs
      DERIVED_TAG="localhost/bootc-test:harness-$(date +%s)-$$-$RANDOM"
      if podman image exists "${DERIVED_TAG}" 2>/dev/null || [ -n "$(podman images -q "${DERIVED_TAG}" 2>/dev/null || true)" ]; then
        die "Generated image tag '${DERIVED_TAG}' already exists."
      fi
    fi
  fi

  log_info "Building derived bootc image from: ${BASE_IMAGE_RESOLVED}"
  log_info "Target tag: ${DERIVED_TAG}"

  podman build \
    --build-arg BASE_IMAGE="${BASE_IMAGE_RESOLVED}" \
    -f "${BUILD_CONTEXT_DIR}/Containerfile" \
    -t "${DERIVED_TAG}" \
    "${BUILD_CONTEXT_DIR}"

  # 5. Capture new image ID
  CREATED_IMAGE_ID="$(podman images -q --no-trunc "${DERIVED_TAG}" 2>/dev/null || true)"
  if [ -z "${CREATED_IMAGE_ID}" ]; then
    log_warn "Could not resolve image ID for built tag ${DERIVED_TAG}"
  else
    log_info "Derived image successfully created with ID: ${CREATED_IMAGE_ID}"
  fi

  # shellcheck disable=SC2034
  DERIVED_IMAGE_TAG="${DERIVED_TAG}"
  # shellcheck disable=SC2034
  DERIVED_IMAGE_ID="${CREATED_IMAGE_ID:-none}"
}
