# bootc-test-harness

A lightweight, project-agnostic test harness for Fedora-family `bootc` container images.

Milestone 1 is intentionally scoped as an **RPM/dnf5-oriented Fedora-family bootc harness**. It automates:
- Resolving and logging immutable base image digests via `skopeo` (or accepting already-pinned digest references directly).
- Assembling disposable derived bootc container images with Podman.
- Installing caller-supplied local RPM files using `dnf5` with ephemeral build mounts (`/var/cache`, `/var/log`, `/run`, `/tmp`).
- Executing an optional caller-provided validation script inside an ephemeral `/tmp/work` tmpfs workdir with argv-safe argument passthrough.
- Running mandatory `bootc container lint` static structural validation.
- Ownership-safe image lifecycle management and cleanup.
- Clear error propagation and provenance reporting.

---

## Architectural Model

```text
Reusable CLI (bin/bootc-test)
              ↑
Thin GitHub Action Wrapper (action.yml)
```

The harness contains **zero** project-specific domain knowledge. Package naming, dependency resolution, dracut module setup, and specific test assertions remain strictly caller responsibilities.

---

## Prerequisites

The following host utilities are required:
- `podman`
- `skopeo`
- `jq`

---

## CLI Usage

```bash
bootc-test [OPTIONS] -- [test-script arguments...]
```

### Options

| Option | Description | Required |
| :--- | :--- | :--- |
| `--base-image <ref>` | Base bootc container reference (tag or digest). For tags (e.g. `ghcr.io/ublue-os/bazzite-deck:stable`), the immutable digest is resolved. For already pinned digests (`image@sha256:...`), it is used directly. | Yes |
| `--rpms-dir <path>` | Path to directory containing pre-staged `.rpm` files to install. Must contain at least one `.rpm`. | Yes |
| `--test-script <path>` | Path to validation script to run inside the container during image build. | No |
| `--tag <image-tag>` | Custom local image tag. Defaults to a unique harness-owned tag (`localhost/bootc-test:harness-<timestamp>-<pid>-<rand>`). | No |
| `--keep-image` | Preserve the derived image after test completion (default: false). | No |
| `-v, --verbose` | Enable verbose logging (`set -x`). | No |
| `-h, --help` | Display usage instructions. | No |
| `-- [args...]` | Argv-safe passthrough to the test script, preserved without eval or shell reparsing. | No |

### Example Local Invocation

```bash
bin/bootc-test \
  --base-image "ghcr.io/ublue-os/bazzite-deck:stable" \
  --rpms-dir "target-rpms" \
  --test-script "tests/test-dracut-bazzite.sh" \
  -- /tmp/work
```

---

## GitHub Action Usage

The repository provides a composite action (`action.yml`) that wraps `bin/bootc-test` and ensures prerequisites are installed:

```yaml
- name: Run bootc integration smoke test
  uses: jaredbartimus/bootc-test-harness@<EXACT_COMMIT_SHA>
  with:
    base-image: ghcr.io/ublue-os/bazzite-deck:stable
    rpms-dir: target-rpms
    test-script: tests/test-dracut-bazzite.sh
    test-args: /tmp/work
```

> **Note**: Pin to the exact commit SHA that reproduces your verified behavior.

### Action Inputs

| Input | Description | Required | Default |
| :--- | :--- | :--- | :--- |
| `base-image` | Base image reference (tag or digest) | Yes | |
| `rpms-dir` | Directory containing caller `.rpm` files | Yes | |
| `test-script` | Path to validation script | No | `''` |
| `test-args` | Arguments to pass after `--` (one non-empty argument per line, blank lines skipped) | No | `''` |
| `tag` | Custom derived image tag | No | `''` |
| `keep-image` | Keep derived image after test | No | `'false'` |

### Action Outputs

| Output | Description |
| :--- | :--- |
| `base-image-requested` | The requested base reference |
| `base-image-resolved` | The immutable base reference (`image@sha256:...`) |
| `derived-image-tag` | Tag of the derived test container |
| `derived-image-id` | Image ID of the derived test container |

---

## Trust Boundary

See [SECURITY.md](SECURITY.md) for details on the execution trust boundary. In brief:
- Caller RPM scriptlets execute with root privileges during package installation.
- Caller validation scripts run with root privileges during container build.
- Intended for testing trusted packages and test suites.

---

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
