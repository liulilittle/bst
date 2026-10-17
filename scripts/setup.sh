#!/usr/bin/env bash
# Host preparation for bst (Linux / WSL / macOS).  One command that installs
# everything the build scripts need, so "get the repo and build" really works:
#
#   scripts/setup.sh --all          # everything below
#   scripts/setup.sh --with-cross   # apt cross toolchains + qemu-user
#   scripts/setup.sh --with-android # fetch the pinned Android NDK
#   scripts/setup.sh --with-libbpf  # consistent libbpf + bpftool (liburing tests)
#
# Everything is idempotent; rerunning is safe.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

WITH_CROSS=0; WITH_ANDROID=0; WITH_LIBBPF=0
while [ $# -gt 0 ]; do
    case "$1" in
        --all)          WITH_CROSS=1; WITH_ANDROID=1; WITH_LIBBPF=1; shift ;;
        --with-cross)   WITH_CROSS=1; shift ;;
        --with-android) WITH_ANDROID=1; shift ;;
        --with-libbpf)  WITH_LIBBPF=1; shift ;;
        -h|--help)      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) bst_die "unknown option '$1' (see --help)" ;;
    esac
done

HF="$(bst_host_family)"

apt_install() { # <packages...>
    [ "$#" -gt 0 ] || return 0
    if command -v apt-get >/dev/null 2>&1; then
        bst_info "apt-get install: $*"
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" \
            || bst_die "apt-get install failed: $*"
    else
        bst_warn "not a Debian/Ubuntu host -- install these yourself: $*"
    fi
}

setup_base() {
    case "$HF" in
        linux)
            apt_install build-essential make curl tar git ca-certificates perl \
                        autoconf automake libtool pkg-config unzip zip \
                        file patch bc
            ;;
        macos)
            if ! xcode-select -p >/dev/null 2>&1; then
                bst_warn "Xcode Command Line Tools missing -- run: xcode-select --install"
            fi
            command -v brew >/dev/null 2>&1 || bst_warn "Homebrew not found (optional); core tools come from Xcode CLT"
            ;;
        *) bst_die "setup.sh supports Linux/WSL/macOS; on Windows use scripts/build.ps1 (it provisions the MSVC side)" ;;
    esac
}

setup_cross() {
    if [ "$HF" != linux ]; then
        bst_warn "--with-cross is Linux-only; skipped"
        return 0
    fi
    apt_install qemu-user
    # one cross gcc per cross site in ci/site-matrix.env
    local site pkgs=()
    for site in $(bst_sites | grep -E '^linux-(aarch64|armv7|riscv64|ppc64le|s390x|i686)$'); do
        case "$site" in
            linux-aarch64) pkgs+=(gcc-aarch64-linux-gnu libc6-dev-arm64-cross linux-libc-dev-arm64-cross) ;;
            linux-armv7)   pkgs+=(gcc-arm-linux-gnueabihf libc6-dev-armhf-cross linux-libc-dev-armhf-cross) ;;
            linux-riscv64) pkgs+=(gcc-riscv64-linux-gnu libc6-dev-riscv64-cross linux-libc-dev-riscv64-cross) ;;
            linux-ppc64le) pkgs+=(gcc-powerpc64le-linux-gnu libc6-dev-ppc64el-cross linux-libc-dev-ppc64el-cross) ;;
            linux-s390x)   pkgs+=(gcc-s390x-linux-gnu libc6-dev-s390x-cross linux-libc-dev-s390x-cross) ;;
            linux-i686)    pkgs+=(gcc-i686-linux-gnu libc6-dev-i386-cross linux-libc-dev-i386-cross) ;;
        esac
    done
    apt_install "${pkgs[@]}"
}

setup_android() {
    bash "$ROOT/scripts/setup-ndk.sh" || bst_die "NDK setup failed"
}

setup_libbpf() {
    # The liburing cBPF tests need a consistent libbpf + bpftool pair newer
    # than Ubuntu 24.04's libbpf 1.3.  Build both from source (pinned) into
    # /usr/local so they match each other and the system headers.
    if [ "$HF" != linux ]; then
        bst_warn "--with-libbpf is Linux-only; skipped"
        return 0
    fi
    local want="1.7.0"
    local have=""
    if [ -f /usr/include/bpf/libbpf_version.h ]; then
        have="$(awk -F' ' '/LIBBPF_MAJOR_VERSION/{m=$3} /LIBBPF_MINOR_VERSION/{n=$3} END{print m "." n}' /usr/include/bpf/libbpf_version.h 2>/dev/null || true)"
    fi
    if [ "$have" = "$want" ]; then
        bst_info "libbpf $want already installed"
    else
        apt_install clang llvm libelf-dev zlib1g-dev
        rm -rf "${BST_TMP:-/tmp}/bst-libbpf"
        git clone --depth 1 --branch "v$want" https://github.com/libbpf/libbpf "${BST_TMP:-/tmp}/bst-libbpf"
        make -C "${BST_TMP:-/tmp}/bst-libbpf/src" -j"$(bst_nproc)"
        sudo make -C "${BST_TMP:-/tmp}/bst-libbpf/src" install
        sudo ldconfig
        bst_info "installed libbpf $want"
    fi
    if ! command -v bpftool >/dev/null 2>&1; then
        apt_install clang llvm libelf-dev zlib1g-dev
        rm -rf "${BST_TMP:-/tmp}/bst-bpftool"
        git clone --depth 1 --branch v7.7.0 https://github.com/libbpf/bpftool "${BST_TMP:-/tmp}/bst-bpftool"
        ( cd "${BST_TMP:-/tmp}/bst-bpftool/src" && make -j"$(bst_nproc)" && sudo make install ) \
            || bst_die "bpftool build failed"
        bst_info "installed bpftool v7.7.0"
    fi
}

bst_info "bst setup on $HF: base=$HF cross=$WITH_CROSS android=$WITH_ANDROID libbpf=$WITH_LIBBPF"
setup_base
[ "$WITH_CROSS" -eq 1 ] && setup_cross
[ "$WITH_ANDROID" -eq 1 ] && setup_android
[ "$WITH_LIBBPF" -eq 1 ] && setup_libbpf
bst_info "setup complete"
