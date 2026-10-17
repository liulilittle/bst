# Supported platforms

> [中文](platforms.zh-CN.md) | English

The authoritative site table is [ci/site-matrix.env](../ci/site-matrix.env);
this document explains it. Each site is one `--site` value with one GNU
triple (also the `dist/` directory name) and one verification level.

## Legend

- **native run** — built and smoke-tested on the host architecture, plus the
  upstream test suite with `--test`.
- **qemu** — cross-built on Linux; the consumer smoke test executes under
  `qemu-user` with the cross sysroot.
- **native exec** — 32-bit binaries executed directly on the x86_64 host
  (kernel ia32 support).
- **compile+link** — artifacts and a consumer smoke program build and link;
  execution needs a device (Android) and is intentionally not attempted.
- **CI-only** — the site is built and tested by GitHub Actions on the native
  OS runner (macOS).

## The matrix

| Site | Triple | Host needed | Libraries | Verification |
| --- | --- | --- | --- | --- |
| `linux-x86_64` | `x86_64-unknown-linux-gnu` | Linux/WSL | openssl, jemalloc, liburing | native run + suite |
| `linux-x86_64-clang` | `x86_64-unknown-linux-gnu` | Linux/WSL | openssl, jemalloc, liburing | native run + suite |
| `linux-aarch64` | `aarch64-unknown-linux-gnu` | Linux/WSL | openssl, jemalloc, liburing | qemu |
| `linux-armv7` | `arm-linux-gnueabihf` | Linux/WSL | openssl, jemalloc, liburing | qemu |
| `linux-riscv64` | `riscv64-unknown-linux-gnu` | Linux/WSL | openssl, jemalloc, liburing | qemu |
| `linux-ppc64le` | `powerpc64le-unknown-linux-gnu` | Linux/WSL | openssl, jemalloc, liburing | qemu |
| `linux-s390x` | `s390x-unknown-linux-gnu` | Linux/WSL | openssl, jemalloc, liburing | qemu |
| `linux-i686` | `i686-unknown-linux-gnu` | Linux/WSL | openssl, jemalloc, liburing | native exec |
| `windows-msvc-x64` | `x86_64-pc-windows-msvc` | Windows | openssl, jemalloc | native run |
| `windows-msvc-x86` | `i686-pc-windows-msvc` | Windows | openssl, jemalloc | native run |
| `windows-msvc-arm64` | `aarch64-pc-windows-msvc` | Windows | openssl | compile+link |
| `macos-arm64` | `arm64-apple-darwin` | macOS | openssl, jemalloc | native run + suite (CI) |
| `macos-x64` | `x86_64-apple-darwin` | macOS | openssl, jemalloc | native run + suite (CI) |
| `android-arm64-v8a` | `aarch64-linux-android` | Linux/WSL | openssl, jemalloc | compile+link |
| `android-armeabi-v7a` | `armv7a-linux-androideabi` | Linux/WSL | openssl, jemalloc | compile+link |
| `android-x86_64` | `x86_64-linux-android` | Linux/WSL | openssl, jemalloc | compile+link |
| `android-x86` | `i686-linux-android` | Linux/WSL | openssl, jemalloc | compile+link |

## Platform notes

### Linux cross sites
Built with the Ubuntu cross toolchains
(`gcc-<arch>-linux-gnu`, `qemu-user`); `scripts/setup.sh --with-cross`
installs everything. The consumer smoke test runs under `qemu-user -L
/usr/<triple>`, so a broken artifact cannot pass. `linux-i686` executes
natively (the x86_64 kernel runs 32-bit ELF) and needs
`libc6-dev-i386-cross` + `linux-libc-dev-i386-cross`.

### Windows
- The MSVC environment is loaded by `scripts/build.ps1` (Visual Studio 2022
  with the C++ workload). NASM (openssl x64/x86) and Strawberry Perl are
  provisioned portably into `.cache/tools/` when missing — no admin rights.
- `windows-msvc-arm64`: openssl only. jemalloc's official MSVC project
  files (`msvc/jemalloc_vc2022.sln`) ship x64/Win32 only, so the site
  refuses jemalloc with an explicit message instead of producing something
  broken.
- Windows builds are native (no emulation); the smoke test runs the built
  artifacts directly.

### macOS
- Apple Silicon first: `macos-arm64` is the primary site; `macos-x64` is
  built with `-arch x86_64` and also works from an arm64 host.
- CI builds both sites on `macos-14` runners. Locally any Mac with Xcode
  Command Line Tools works.

### Android
- NDK r27c (LTS), API level 24, fetched by `scripts/setup-ndk.sh` with a
  pinned sha256.
- All four ABI builds compile, install and link a consumer smoke program;
  execution requires an attached device/emulator and is out of scope for
  the toolkit's default gate.
- jemalloc is configured with `--disable-cxx` on Android (bionic declares
  `malloc_usable_size` with `nothrow`, which conflicts with jemalloc's C++
  operator-override translation unit; the C++ integration is redundant on
  bionic anyway).

### liburing
Linux only, by construction (io_uring is a Linux kernel interface). The
site table only lists it for `linux-*` sites; any other request fails with
an explicit message.

## Versions

| Library | Default | Line | Upgrade path |
| --- | --- | --- | --- |
| openssl | 3.5.9 | LTS (4.0.3 also pinned) | `scripts/pin.sh openssl <v> --update-default` |
| jemalloc | 5.4.0 | current stable | `scripts/pin.sh jemalloc <v> --update-default` |
| liburing | 2.15 | current stable | `scripts/pin.sh liburing <v> --update-default` |

Every version row carries the official source URL and its sha256; builds
verify before touching anything.
