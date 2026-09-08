#!/usr/bin/env bash
#
# tests/test_cli.sh - CLI and unit test suite for bootc-test-harness
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTC_TEST="${REPO_ROOT}/bin/bootc-test"

pass=0
fail=0

assert_success() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  PASS: ${desc}"
    pass=$((pass + 1))
  else
    echo "  FAIL: ${desc}" >&2
    fail=$((fail + 1))
  fi
}

assert_failure() {
  local desc="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    echo "  PASS: ${desc} (failed as expected)"
    pass=$((pass + 1))
  else
    echo "  FAIL: ${desc} (expected command to fail, but it succeeded)" >&2
    fail=$((fail + 1))
  fi
}

assert_output_contains() {
  local desc="$1"
  local expected="$2"
  shift 2
  local out
  out="$("$@" 2>&1 || true)"
  if [[ "${out}" == *"${expected}"* ]]; then
    echo "  PASS: ${desc}"
    pass=$((pass + 1))
  else
    echo "  FAIL: ${desc}" >&2
    echo "    Expected to contain: ${expected}" >&2
    echo "    Actual output: ${out}" >&2
    fail=$((fail + 1))
  fi
}

echo "=== Running bootc-test-harness CLI Unit Tests ==="

# 1. Help message
assert_success "--help displays usage and exits 0" "${BOOTC_TEST}" --help
assert_success "-h displays usage and exits 0" "${BOOTC_TEST}" -h

# 2. Missing required parameters
assert_failure "Exits with error when no arguments provided" "${BOOTC_TEST}"
assert_output_contains "Error message when --base-image is missing" \
  "--base-image is required" "${BOOTC_TEST}" --rpms-dir .

assert_output_contains "Error message when --rpms-dir is missing" \
  "--rpms-dir is required" "${BOOTC_TEST}" --base-image "example.com/base:tag"

# 3. Missing argument values
assert_output_contains "Error on trailing --base-image without value" \
  "--base-image requires a value" "${BOOTC_TEST}" --base-image

assert_output_contains "Error on trailing --rpms-dir without value" \
  "--rpms-dir requires a value" "${BOOTC_TEST}" --rpms-dir

# 4. RPM directory validation
temp_test_dir="$(mktemp -d -t bootc-test-unit.XXXXXX)"
trap 'rm -rf "${temp_test_dir}"' EXIT

assert_output_contains "Error on non-existent --rpms-dir" \
  "RPM directory not found" "${BOOTC_TEST}" --base-image "foo:bar" --rpms-dir "${temp_test_dir}/does-not-exist"

assert_output_contains "Error on empty --rpms-dir containing no .rpm files" \
  "No .rpm files found in directory" "${BOOTC_TEST}" --base-image "foo:bar" --rpms-dir "${temp_test_dir}"

# 5. Test script validation
touch "${temp_test_dir}/test.rpm"
assert_output_contains "Error when test arguments provided after '--' without --test-script" \
  "Arguments provided after '--' but no --test-script was specified" \
  "${BOOTC_TEST}" --base-image "foo:bar" --rpms-dir "${temp_test_dir}" -- arg1 arg2

assert_output_contains "Error on non-existent --test-script" \
  "Test script not found" \
  "${BOOTC_TEST}" --base-image "foo:bar" --rpms-dir "${temp_test_dir}" --test-script "${temp_test_dir}/missing-script.sh"

# 6. Digest resolution unit tests
echo ""
echo "=== Testing Digest Resolution (lib/digest.sh) ==="
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/digest.sh
source "${REPO_ROOT}/lib/digest.sh"

# Pinned digest should be accepted directly without invoking skopeo
resolve_base_image "ghcr.io/ublue-os/bazzite-deck@sha256:4df96fd78f44bc298fc5474c58a19fe879969b924bc5c60e00482d30885792e3"
if [ "${BASE_IMAGE_RESOLVED}" = "ghcr.io/ublue-os/bazzite-deck@sha256:4df96fd78f44bc298fc5474c58a19fe879969b924bc5c60e00482d30885792e3" ]; then
  echo "  PASS: Already-pinned digest reference preserved exactly"
  pass=$((pass + 1))
else
  echo "  FAIL: Already-pinned digest reference altered" >&2
  fail=$((fail + 1))
fi

# Tagged reference resolution with mock skopeo
mock_bin_dir="${temp_test_dir}/mock_bin"
mkdir -p "${mock_bin_dir}"
cat <<'MOCK' > "${mock_bin_dir}/skopeo"
#!/usr/bin/env bash
if [ "$1" = "inspect" ]; then
  echo '{"Digest": "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"}'
  exit 0
fi
echo "Unexpected skopeo invocation" >&2
exit 1
MOCK
chmod +x "${mock_bin_dir}/skopeo"

OLD_PATH="${PATH}"
PATH="${mock_bin_dir}:${PATH}"

resolve_base_image "ghcr.io/ublue-os/bazzite-deck:stable"
if [ "${BASE_IMAGE_RESOLVED}" = "ghcr.io/ublue-os/bazzite-deck@sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890" ]; then
  echo "  PASS: Tagged reference correctly resolved and tag replaced with @digest"
  pass=$((pass + 1))
else
  echo "  FAIL: Expected ghcr.io/ublue-os/bazzite-deck@sha256:abcdef..., got ${BASE_IMAGE_RESOLVED}" >&2
  fail=$((fail + 1))
fi

# Registry with port
resolve_base_image "localhost:5000/my-custom/image:v1.2.3"
if [ "${BASE_IMAGE_RESOLVED}" = "localhost:5000/my-custom/image@sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890" ]; then
  echo "  PASS: Registry with port and tag correctly resolved to @digest"
  pass=$((pass + 1))
else
  echo "  FAIL: Port preservation failed, got ${BASE_IMAGE_RESOLVED}" >&2
  fail=$((fail + 1))
fi

PATH="${OLD_PATH}"

# 7. Argv-safe serialization test
echo ""
echo "=== Testing Argv-Safe Passthrough Serialization ==="
test_script_path="${temp_test_dir}/test_receiver.sh"
cat <<'RECEIVER' > "${test_script_path}"
#!/usr/bin/env bash
set -euo pipefail
echo "Arg count: $#"
for i in "$@"; do
  echo "ARG: [${i}]"
done
RECEIVER
chmod +x "${test_script_path}"

# Simulate context runner script generation as done in lib/build.sh
# shellcheck disable=SC2016
sample_args=(
  "/tmp/work"
  "arg with spaces"
  'arg with "quotes" and $variables'
  "multi
line"
)

runner_test="${temp_test_dir}/run-test.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  echo 'args=()'
  for arg in "${sample_args[@]}"; do
    printf 'args+=(%q)\n' "${arg}"
  done
  # shellcheck disable=SC2016
  echo 'if [ -x "'"${test_script_path}"'" ]; then'
  # shellcheck disable=SC2016
  echo '  exec "'"${test_script_path}"'" "${args[@]}"'
  echo 'else'
  # shellcheck disable=SC2016
  echo '  exec /bin/bash "'"${test_script_path}"'" "${args[@]}"'
  echo 'fi'
} > "${runner_test}"
chmod +x "${runner_test}"

output="$("${runner_test}")"
assert_output_contains "Argv count matches exactly" "Arg count: 4" echo "${output}"
assert_output_contains "Argument with spaces preserved" "ARG: [arg with spaces]" echo "${output}"
# shellcheck disable=SC2016
assert_output_contains "Argument with quotes preserved" 'ARG: [arg with "quotes" and $variables]' echo "${output}"
assert_output_contains "Multi-line argument preserved" "ARG: [multi"$'\n'"line]" echo "${output}"

# 8. Tag collision rejection
echo ""
echo "=== Testing Custom Tag Collision Rejection ==="
mock_podman_dir="${temp_test_dir}/mock_podman_bin"
mkdir -p "${mock_podman_dir}"
cat <<'MOCK_PODMAN' > "${mock_podman_dir}/podman"
#!/usr/bin/env bash
if [ "$1" = "image" ] && [ "$2" = "exists" ]; then
  if [ "$3" = "localhost/pre-existing:tag" ]; then
    exit 0
  fi
  exit 1
fi
if [ "$1" = "images" ]; then
  if [[ "$*" == *"localhost/pre-existing:tag"* ]]; then
    echo "existing-img-id-12345"
    exit 0
  fi
  exit 0
fi
exit 0
MOCK_PODMAN
chmod +x "${mock_podman_dir}/podman"

cat <<'MOCK_SKOPEO' > "${mock_podman_dir}/skopeo"
#!/usr/bin/env bash
echo '{"Digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111"}'
MOCK_SKOPEO
chmod +x "${mock_podman_dir}/skopeo"

OLD_PATH="${PATH}"
PATH="${mock_podman_dir}:${PATH}"

assert_output_contains "Fails cleanly when custom --tag already exists" \
  "Image tag 'localhost/pre-existing:tag' already exists. Refusing to overwrite pre-existing image tag." \
  "${BOOTC_TEST}" --base-image "foo:bar" --rpms-dir "${temp_test_dir}" --tag "localhost/pre-existing:tag"

PATH="${OLD_PATH}"

echo ""
echo "=== Test Summary ==="
echo "Passed: ${pass}"
echo "Failed: ${fail}"

[ "${fail}" -eq 0 ]
