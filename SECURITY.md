# Security & Trust Boundary

## Execution Trust Boundary

`bootc-test-harness` is designed as a testing tool for container images and RPM packages. It builds a derived container using Podman and executes build-time steps.

Consumers of this harness should understand the following security characteristics:

1. **RPM Package Scriptlet Execution**:
   When caller-provided RPMs are installed via `dnf5 install -y /tmp/rpms/*.rpm`, package scriptlets (such as `%pre`, `%post`, `%preun`, `%postun`, and file triggers) are executed with root privileges inside the container build environment.

2. **Validation Test Script Execution**:
   The caller-supplied test script (`--test-script`) is deliberately mounted into the derived container and executed as root during the image build process (`RUN /bin/bash /tmp/test-assets/run-test.sh`).

3. **Ephemeral Build Mounts**:
   The harness uses ephemeral cache (`/var/cache`, `/var/log`) and tmpfs (`/run`, `/tmp`, `/tmp/work`) mounts during the build. These prevent temporary test artifacts, package caches, and runtime state from leaking into container image layers or lingering across runs.

4. **Intended Usage**:
   `bootc-test-harness` is intended for **trusted test inputs**. Do not supply untrusted RPM packages or untrusted test scripts to the harness without appropriate container isolation or sandboxing.
