#!/usr/bin/env bash
#
# tests/fixtures/build-fixture-rpm.sh - Build dummy-test RPM for integration tests
#
set -euo pipefail

out_dir="${1:-target-rpms}"
mkdir -p "${out_dir}"

topdir="$(mktemp -d -t rpmtop.XXXXXX)"
trap 'rm -rf "${topdir}"' EXIT

mkdir -p "${topdir}/"{BUILD,RPMS,SOURCES,SPECS,SRPMS}
spec_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dummy-test.spec"

rpmbuild \
  --define "_topdir ${topdir}" \
  -bb "${spec_file}"

find "${topdir}/RPMS" -type f -name "*.rpm" -exec cp {} "${out_dir}/" \;
echo "Built fixture RPMs in ${out_dir}:"
ls -la "${out_dir}"
