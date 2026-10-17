# bst

> [中文](README.zh-CN.md) | English

[![ci](https://github.com/liulilittle/bst/actions/workflows/ci.yml/badge.svg)](https://github.com/liulilittle/bst/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`bst` is a cross-platform build toolkit for C/C++ libraries that are
notorious to compile by hand. Get the repository, run **one command**, and
get a correct build for the platform you asked for — sources verified,
toolchain located, upstream quirks handled, downstream-ready output staged.

No researching. No half-day yak-shaving. The knowledge lives in the scripts.

## Quick start

| Host | Command |
| --- | --- |
| Linux / WSL | `scripts/build.sh openssl --site linux-aarch64` |
| macOS | `scripts/build.sh jemalloc --site macos-arm64` |
| Windows (PowerShell) | `.\scripts\build.ps1 openssl -Site windows-msvc-x64` |
| Windows → Linux/Android | same as above with a Linux site; `build.ps1` delegates to WSL automatically |

First time on a fresh machine:

```sh
# Linux / WSL: cross toolchains, qemu, NDK, libbpf/bpftool for liburing tests
scripts/setup.sh --all

# Windows: build.ps1 provisions the MSVC environment itself (Visual Studio
# 2022 required) and fetches portable NASM + Strawberry Perl when missing.
```

See [docs/building.md](docs/building.md) for every option and example.

## Libraries

| Library | Source of truth | Notes |
| --- | --- | --- |
| [openssl](https://www.openssl.org) | pinned release tarball + sha256 | Configure target chosen per site; `apps/openssl` included |
| [jemalloc](https://jemalloc.net) | pinned release tarball + sha256 | autotools on unix; official MSVC solution on Windows; Android builds with `--disable-cxx` (bionic's `malloc_usable_size` nothrow clash) |
| [liburing](https://github.com/axboe/liburing) | pinned tag tarball + sha256 | Linux only; upstream test suite selectable |

Each build stages `dist/<library>/<triple>/` with `include/`, `lib/`,
`bin/`, and a `BUILD-INFO.txt` recording the exact version, site, flags and
source checksum.

## Supported platforms

Hosts build the platforms that belong to them; anything else is refused with
a clear message (Windows hosts delegate Linux/Android sites through WSL).

| Platform | Sites | Libraries |
| --- | --- | --- |
| Linux x86_64 (native) | gcc, clang | openssl, jemalloc, liburing |
| Linux cross (qemu-verified smoke) | aarch64, armv7hf, riscv64, ppc64le, s390x, i686 | openssl, jemalloc, liburing |
| Windows MSVC | x64, x86, arm64 | openssl (x64/x86/arm64), jemalloc (x64/x86) |
| macOS | arm64 (Apple Silicon), x64 | openssl, jemalloc |
| Android NDK (API 24) | arm64-v8a, armeabi-v7a, x86_64, x86 | openssl, jemalloc |

The full matrix with verification levels is in
[docs/platforms.md](docs/platforms.md).

## Get prebuilt artifacts from CI

Every CI run builds **and uploads** per-site tarballs
(`bst-<lib>-<version>-<triple>.tar.gz`): open the workflow run and download
them from the *Artifacts* section. Tagging a release (`git tag v0.1.0`)
builds the same matrix and attaches every tarball plus `SHA256SUMS` to the
GitHub release.

## Growing the toolkit

Adding the next library is a checklist, not a project: a recipe file, a
site-table row per supported site, CI matrix rows, and a smoke test. See
[docs/adding-a-library.md](docs/adding-a-library.md).

Upstream needs a fix to build? Drop a patch into `patches/<lib>/` — it is
applied automatically (and checksum-stamped) after the tarball is extracted.

## Repository layout

```
scripts/build.sh          main entry (Linux/WSL/macOS)
scripts/build.ps1         main entry (Windows; WSL delegation)
scripts/setup.sh          one-shot host preparation
scripts/setup-ndk.sh      pinned Android NDK fetch
scripts/pin.sh            pin a new upstream version (upgrade path)
scripts/lib/recipes/      one recipe per library
ci/site-matrix.env        the single source of truth for sites
ci/versions.env           pinned versions + sha256 ledger
patches/                  optional upstream build fixes
docs/                     bilingual documentation
```

## License

MIT (see [LICENSE](LICENSE)); upstream libraries keep their own licenses
(see [THIRD-PARTY.md](THIRD-PARTY.md)).
