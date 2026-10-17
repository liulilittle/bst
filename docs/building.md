# Building libraries with bst

> [中文](building.zh-CN.md) | English

This document covers everything the build entry points do: requirements,
options, per-host workflows, outputs, tests, upgrades, patches and
troubleshooting. The supported site matrix is in
[platforms.md](platforms.md); the extensibility contract is in
[adding-a-library.md](adding-a-library.md).

## Requirements

| Host | What you need | One-shot preparation |
| --- | --- | --- |
| Linux | gcc/make/curl/tar; per-site cross toolchains + `qemu-user` for cross smoke; NDK for Android sites | `scripts/setup.sh --all` |
| WSL (Windows) | same as Linux (Ubuntu 24.04 distro recommended); `sudo` for package setup | `scripts/setup.sh --all` inside WSL |
| macOS | Xcode Command Line Tools (`xcode-select --install`) | — |
| Windows | Visual Studio 2022 (Desktop C++ workload); Git for Windows (bash) | `scripts/build.ps1` loads the MSVC environment and provisions portable NASM + Strawberry Perl automatically (`winget install NASM.NASM` / `StrawberryPerl.StrawberryPerl` also work) |

Nothing else, and no research: every download is a pinned, checksum-verified
upstream tarball.

## One command

```sh
scripts/build.sh <openssl|jemalloc|liburing> [options]
```

| Option | Meaning |
| --- | --- |
| `--site <site>` | target site (default: this host's native site); see `scripts/build.sh <lib> --list-sites` |
| `--version <v>` | upstream version; must be pinned in `ci/versions.env` (defaults per library) |
| `--variant static\|shared\|both` | library flavor (default `static`) |
| `--test` | additionally run the upstream test suite (see *Tests* below) |
| `--clean` | wipe this library's build tree and staged output first |
| `--jobs <n>` | build parallelism (default: all cores) |
| `--skip-smoke` | skip the consumer smoke test |
| `--list-sites` | print every site this library supports |

On Windows the entry point is PowerShell:

```powershell
.\scripts\build.ps1 openssl -Site windows-msvc-x64
.\scripts\build.ps1 jemalloc -Site windows-msvc-x86 -Variant both
.\scripts\build.ps1 liburing -Site linux-aarch64     # delegated to WSL
.\scripts\build.ps1 openssl -All                     # every buildable site
```

`build.ps1` maps to the same options (`-Version`, `-Variant`, `-Test`,
`-Clean`, `-SkipSmoke`, `-WslDistro <name>`, `-NoWsl`).

## Host/target policy

Windows hosts build Windows sites. Linux hosts (including WSL) build Linux
and Android sites. macOS hosts build macOS sites. A mismatched request fails
immediately with the exact command to run instead; `build.ps1` performs the
WSL delegation for you (`-NoWsl` opts out).

## Outputs

```
dist/<library>/<triple>/
  include/            public headers (install layout)
  lib/                static and/or shared libraries
  bin/                tools where the library ships them (openssl)
  BUILD-INFO.txt      version, site, triple, variants, compiler, tarball sha256
```

- `ci-logs/<library>-<site>.log` — the full build log.
- `.cache/src/` — verified upstream tarballs (reused across builds).
- `.build/` — build trees (removed by `--clean`).

On WSL, when the repository lives on `/mnt/*` (Windows drive), build trees
and caches are automatically placed on the Linux filesystem
(`$HOME/.cache/bst/...`) because drvfs is prohibitively slow for build
trees; `dist/` and logs deliberately stay in the repository so Windows-side
tooling can pick them up. Override with `BST_BUILD=<dir>` /
`BST_CACHE=<dir>`.

## Tests

`--test` enables the upstream test suite; what runs depends on the library
and the site:

| Library | Native Linux/macOS | Cross sites | Windows |
| --- | --- | --- | --- |
| openssl | `make test` (full perl harness) | smoke only (harness is not qemu-capable) | `nmake test` |
| jemalloc | `make check` (unit suite) | smoke only | smoke only (upstream suite is not wired for MSVC yet) |
| liburing | curated sub-set of `runtests.sh` (deterministic across kernels); `BST_LIBURING_TESTS=all` runs everything; `BST_LIBURING_TEST_EXCLUDE="t1 t2"` excludes | smoke only | n/a (Linux only) |

Every site always builds and runs a **consumer smoke test**: a small
program compiled against the staged artifacts, linked like a real consumer
would, and executed (through `qemu-user` with the cross sysroot on cross
sites; Android links but does not execute — no device runner is attached).

The liburing cBPF tests need a consistent modern libbpf + bpftool pair
(Ubuntu 24.04 ships libbpf 1.3 which is older than the suite expects);
`scripts/setup.sh --with-libbpf` builds a pinned pair from source.

## Getting prebuilt artifacts from CI

- **Workflow artifacts**: every CI job uploads
  `bst-<lib>-<version>-<triple>.tar.gz` (Actions → run → Artifacts).
- **Releases**: push a tag (`git tag v0.1.0 && git push origin v0.1.0`);
  the release workflow builds the whole matrix and attaches every tarball
  plus `SHA256SUMS` to the GitHub release.

## Upgrading a library version

```sh
scripts/pin.sh openssl 4.0.3 --update-default   # download, sha256, record
scripts/build.sh openssl --site linux-x86_64    # build it
```

`pin.sh` appends the `lib|version|url|sha256` row to `ci/versions.env`;
without `--update-default` the new version is opt-in via `--version 4.0.3`.
Builds verify the checksum and fail closed on any mismatch.

## Applying patches

Drop `-p1` unified diffs under `patches/<lib>/<version>/` (exact version) or
`patches/<lib>/` (all versions); they are applied in filename order right
after extraction. Changing the patch set afterwards requires `--clean` (the
tree is stamped to prevent double-application). See
[patches/README.md](../patches/README.md).

## Host preparation

```sh
scripts/setup.sh --all            # base tools + cross toolchains + NDK + libbpf
scripts/setup.sh --with-cross     # apt cross toolchains + qemu-user only
scripts/setup.sh --with-android   # pinned NDK fetch (sha256-verified)
scripts/setup.sh --with-libbpf    # consistent libbpf + bpftool for liburing tests
```

## Running everything

```sh
scripts/build-all.sh              # every (lib, site) this host can build
scripts/build-all.sh --lib openssl --keep-going
```

`build-all.sh` drives `scripts/ci/build-test.sh`, the exact code path CI
uses — a local run and a CI job are the same program.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `missing 'qemu-aarch64'` | `scripts/setup.sh --with-cross` |
| `Android NDK (r27c) not found` | `scripts/setup.sh --with-android` or export `ANDROID_NDK=<root>` |
| liburing tests fail to compile BPF probes | `scripts/setup.sh --with-libbpf` (consistent libbpf + bpftool pair) |
| Windows: `cl.exe not in PATH` | run through `scripts/build.ps1` (loads the Visual Studio environment) |
| Windows: NASM/Perl download stalled | rerun — downloads resume (`curl -C -`); manual installs also work |
| WSL builds feel slow but work | normal for `/mnt/*`; bst already redirects build trees to ext4 (`BST_BUILD` override available) |
| `sha256 mismatch` | the cached tarball is corrupt: delete it from `.cache/src/` and rerun; if upstream re-released a file, re-pin with `scripts/pin.sh` |
