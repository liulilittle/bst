# shellcheck shell=bash
# bst common library: site resolution, toolchain checks, download + sha256
# verification, patching, staging and small portability helpers.
#
# Sourced by scripts/build.sh and the recipes in scripts/lib/recipes/.
# Sourced code must stay bash 3.2 compatible (macOS ships bash 3.2).

BST_VERSION="0.1.0"

# Storage defaults.  A repo on a WSL /mnt/* drive is drvfs (painfully slow for
# build trees), so there the heavy state defaults to the Linux filesystem;
# dist/ deliberately stays inside the repo on every platform.  An explicitly
# set BST_BUILD / BST_CACHE always wins.
wsl_slow_fs() {
    case "$(uname -r 2>/dev/null)" in *microsoft*|*WSL*) ;; *) return 1 ;; esac
    case "${BST_ROOT:-}" in /mnt/*) return 0 ;; *) return 1 ;; esac
}
if [ -z "${BST_BUILD:-}" ]; then
    if wsl_slow_fs; then
        BST_BUILD="$HOME/.cache/bst/build-$(printf '%s' "$BST_ROOT" | cksum | awk '{print $1}')"
    else
        BST_BUILD="$BST_ROOT/.build"
    fi
fi
if [ -z "${BST_CACHE:-}" ]; then
    if wsl_slow_fs; then
        BST_CACHE="$HOME/.cache/bst/cache-$(printf '%s' "$BST_ROOT" | cksum | awk '{print $1}')"
    else
        BST_CACHE="$BST_ROOT/.cache"
    fi
fi
export BST_BUILD BST_CACHE

# ---------------------------------------------------------------------------
# logging / errors
# ---------------------------------------------------------------------------
bst_die() { printf 'bst: error: %s\n' "$*" >&2; exit 1; }
bst_warn() { printf 'bst: warning: %s\n' "$*" >&2; }
bst_info() { printf 'bst: %s\n' "$*"; }

bst_require_cmd() { # <cmd> <install hint>
    command -v "$1" >/dev/null 2>&1 || bst_die "missing '$1' -- install it: $2"
}

# ---------------------------------------------------------------------------
# portability helpers
# ---------------------------------------------------------------------------
bst_sha256() { # <file> -> "sha  file"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1"
    else
        shasum -a 256 "$1"
    fi
}

bst_sha256_of() { # <file> -> bare digest
    bst_sha256 "$1" | awk '{print $1}'
}

bst_nproc() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null || echo 4
    else
        echo "${NUMBER_OF_PROCESSORS:-4}"
    fi
}

# ---------------------------------------------------------------------------
# host detection
# ---------------------------------------------------------------------------
bst_host_family() { # linux | macos | windows | "" (unknown)
    case "$(uname -s)" in
        Linux) echo linux ;;
        Darwin) echo macos ;;
        MINGW*|MSYS*|CYGWIN*) echo windows ;;
        *) echo "" ;;
    esac
}

bst_host_site() { # default --site for this host
    case "$(bst_host_family)" in
        linux)
            case "$(uname -m)" in
                x86_64) echo linux-x86_64 ;;
                aarch64|arm64) echo linux-aarch64 ;;
                *) echo "" ;;
            esac
            ;;
        macos)
            case "$(uname -m)" in
                arm64) echo macos-arm64 ;;
                x86_64) echo macos-x64 ;;
                *) echo "" ;;
            esac
            ;;
        windows) echo windows-msvc-x64 ;;
        *) echo "" ;;
    esac
}

bst_host_accepts_site() { # <family>
    local hf; hf="$(bst_host_family)"
    case "$hf:$1" in
        linux:linux|linux:linux-clang|linux:android) return 0 ;;
        macos:macos) return 0 ;;
        windows:windows) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# site table (ci/site-matrix.env)
# ---------------------------------------------------------------------------
bst_sites() { # all known site keys
    awk -F'|' '{ sub(/\r$/, "") } $1 !~ /^[[:space:]]*#/ && NF >= 8 { print $1 }' "$BST_ROOT/ci/site-matrix.env"
}

bst_sites_for_lib() { # <lib> -> sites that support it
    awk -F'|' -v l="$1" '{ sub(/\r$/, "") } $1 !~ /^[[:space:]]*#/ && NF >= 8 {
            n = split($8, a, " ")
            for (i = 1; i <= n; i++) if (a[i] == l) print $1
        }' "$BST_ROOT/ci/site-matrix.env"
}

site_info() { # <site> -> exports SITE*, validates existence
    local row
    row="$(awk -F'|' -v k="$1" '{ sub(/\r$/, "") } $1 !~ /^[[:space:]]*#/ && $1 == k { print; exit }' "$BST_ROOT/ci/site-matrix.env")"
    [ -n "$row" ] || bst_die "unknown site '$1' (known sites: $(bst_sites | tr '\n' ' '))"
    IFS='|' read -r SITE SITE_TRIPLE SITE_FAMILY SITE_CC SITE_CXX SITE_CROSS SITE_EMU SITE_LIBS <<<"$row"
    SITE_ROW="$row"
}

site_supports_lib() { # <lib>
    case " $SITE_LIBS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

site_is_cross() { [ -n "$SITE_CROSS" ]; }

# ---------------------------------------------------------------------------
# toolchain resolution
# ---------------------------------------------------------------------------
BST_NDK_VERSION="${BST_NDK_VERSION:-27c}"
BST_ANDROID_API="${BST_ANDROID_API:-24}"

bst_ndk_root() {
    local c
    for c in "${ANDROID_NDK:-}" "$BST_CACHE/ndk/android-ndk-r${BST_NDK_VERSION}" ; do
        [ -n "$c" ] && [ -d "$c" ] && [ -f "$c/source.properties" ] && { echo "$c"; return 0; }
    done
    bst_die "Android NDK (r${BST_NDK_VERSION}) not found -- run scripts/setup-ndk.sh or set ANDROID_NDK=<ndk root>"
}

bst_ndk_host_tag() {
    case "$(bst_host_family)" in
        linux) echo linux-x86_64 ;;
        macos) echo darwin-x86_64 ;;
        *) bst_die "Android NDK host tag unknown for this host" ;;
    esac
}

resolve_toolchain() { # exports CC CXX AR RANLIB STRIP NM OBJCOPY + SITE_SYSROOT
    local cc="" cxx="" cross="$SITE_CROSS"
    case "$SITE_FAMILY" in
        linux|linux-clang)
            cc="${SITE_CC:-${cross}gcc}"
            cxx="${SITE_CXX:-${cross}g++}"
            AR="${cross}ar" RANLIB="${cross}ranlib" STRIP="${cross}strip" \
            NM="${cross}nm" OBJCOPY="${cross}objcopy"
            ;;
        android)
            local ndk tc; ndk="$(bst_ndk_root)"; tc="$ndk/toolchains/llvm/prebuilt/$(bst_ndk_host_tag)"
            case "$SITE_TRIPLE" in
                aarch64-linux-android)     cc="$tc/bin/aarch64-linux-android${BST_ANDROID_API}-clang" ;;
                armv7a-linux-androideabi)  cc="$tc/bin/armv7a-linux-androideabi${BST_ANDROID_API}-clang" ;;
                x86_64-linux-android)      cc="$tc/bin/x86_64-linux-android${BST_ANDROID_API}-clang" ;;
                i686-linux-android)        cc="$tc/bin/i686-linux-android${BST_ANDROID_API}-clang" ;;
                *) bst_die "unsupported Android triple '$SITE_TRIPLE'" ;;
            esac
            [ -x "$cc" ] || bst_die "NDK compiler not found: $cc"
            cxx="${cc}++"
            AR="$tc/bin/llvm-ar" RANLIB="$tc/bin/llvm-ranlib" STRIP="$tc/bin/llvm-strip" \
            NM="$tc/bin/llvm-nm" OBJCOPY="$tc/bin/llvm-objcopy"
            ;;
        macos)
            cc=clang; cxx=clang++
            case "$SITE_TRIPLE" in
                arm64-apple-darwin)   SITE_DARWIN_ARCH=arm64 ;;
                x86_64-apple-darwin)  SITE_DARWIN_ARCH=x86_64 ;;
                *) bst_die "unsupported macOS triple '$SITE_TRIPLE'" ;;
            esac
            AR=ar RANLIB=ranlib STRIP=strip NM=nm OBJCOPY=objcopy
            ;;
        windows)
            command -v cl >/dev/null 2>&1 || bst_die "MSVC environment not loaded -- run this site through scripts/build.ps1 (it locates Visual Studio and loads the developer environment)"
            cc=cl; cxx=cl
            AR=lib RANLIB=: STRIP=: NM=: OBJCOPY=:
            ;;
        *) bst_die "unsupported site family '$SITE_FAMILY'" ;;
    esac
    CC="$cc"; CXX="$cxx"
    export CC CXX AR RANLIB STRIP NM OBJCOPY
    SITE_SYSROOT=""
    if site_is_cross && [ "$SITE_FAMILY" != android ]; then
        SITE_SYSROOT="$("$CC" -print-sysroot 2>/dev/null || true)"
        case "$SITE_SYSROOT" in
            ""|"/")
                # Debian-style cross toolchains report "/" (or nothing); the
                # real sysroot is the per-arch tree installed by the packages.
                SITE_SYSROOT="/usr/${SITE_CROSS%-}"
                ;;
        esac
    fi
}

resolve_emulator() { # exports BST_EMU (empty = run natively)
    BST_EMU=""
    case "$SITE_EMU" in
        ""|i686-native) BST_EMU="" ;;
        qemu-*)
            command -v "$SITE_EMU" >/dev/null 2>&1 || \
                bst_die "missing emulator '$SITE_EMU' -- install it: sudo apt-get install qemu-user"
            BST_EMU="$SITE_EMU"
            ;;
        *) bst_die "unknown emulator '$SITE_EMU' in ci/site-matrix.env" ;;
    esac
    export BST_EMU
}

bst_run_exe() { # <exe> [args...] -- run through the emulator when cross
    if [ -n "${BST_EMU:-}" ]; then
        if [ -n "${SITE_SYSROOT:-}" ] && [ -d "$SITE_SYSROOT" ]; then
            "$BST_EMU" -L "$SITE_SYSROOT" "$@"
        else
            "$BST_EMU" "$@"
        fi
    else
        "$@"
    fi
}

# ---------------------------------------------------------------------------
# sources: fetch + verify + extract + patch
# ---------------------------------------------------------------------------
bst_version_row() { # <lib> <version> -> "url|sha256"
    awk -F'|' -v l="$1" -v v="$2" '{ sub(/\r$/, "") } $1 !~ /^[[:space:]]*#/ && $1 == l && $2 == v { print $3 "|" $4; exit }' \
        "$BST_ROOT/ci/versions.env"
}

bst_default_version() { # <lib>
    awk -F'=' -v k="$(echo "$1" | tr '[:lower:]' '[:upper:]')_DEFAULT_VERSION" \
        '{ sub(/\r$/, "") } $1 == k { print $2; exit }' "$BST_ROOT/ci/versions.env"
}

bst_fetch() { # <lib> <version>: download+verify+extract+patch; sets BST_SRC
    local lib="$1" ver="$2" row url sha fname
    row="$(bst_version_row "$lib" "$ver")"
    [ -n "$row" ] || bst_die "no pinned source for '$lib $ver' -- add one with: scripts/pin.sh $lib $ver"
    url="${row%%|*}"; sha="${row#*|}"
    fname="${url##*/}"
    mkdir -p "$BST_CACHE/src"
    BST_TARBALL="$BST_CACHE/src/$fname"
    if [ ! -f "$BST_TARBALL" ]; then
        bst_info "fetching $url"
        if ! curl -fsSL --retry 3 -o "$BST_TARBALL.tmp" "$url"; then
            rm -f "$BST_TARBALL.tmp"
            bst_die "download failed: $url"
        fi
        mv "$BST_TARBALL.tmp" "$BST_TARBALL"
    fi
    local got; got="$(bst_sha256_of "$BST_TARBALL")"
    [ "$got" = "$sha" ] || bst_die "sha256 mismatch for $fname
  expected: $sha
  actual:   $got
  (delete $BST_TARBALL and retry; if upstream re-released the file, re-pin with scripts/pin.sh)"
    bst_info "sha256 ok: $fname"

    BST_SRC="$BST_BUILD/src/$lib-$ver"
    if [ ! -f "$BST_SRC/.bst-extracted" ]; then
        rm -rf "$BST_SRC"
        mkdir -p "$BST_SRC"
        bst_info "extracting $fname"
        tar -xf "$BST_TARBALL" -C "$BST_SRC" --strip-components=1 || bst_die "extract failed: $BST_TARBALL"
        touch "$BST_SRC/.bst-extracted"
    fi
    bst_apply_patches "$lib" "$ver" "$BST_SRC"
}

bst_apply_patches() { # <lib> <version> <srcdir>
    local lib="$1" ver="$2" src="$3" d f sig files=()
    for d in "$BST_ROOT/patches/$lib/$ver" "$BST_ROOT/patches/$lib"; do
        [ -d "$d" ] || continue
        for f in "$d"/*.patch; do
            [ -e "$f" ] || continue
            files+=("$f")
        done
    done
    [ "${#files[@]}" -gt 0 ] || return 0

    sig="$(for f in "${files[@]}"; do bst_sha256_of "$f" | awk '{print $1}'; done)"
    local stamped=""
    [ -f "$src/.bst-patches" ] && stamped="$(cat "$src/.bst-patches")"
    if [ -n "$stamped" ] && [ "$stamped" != "$sig" ]; then
        bst_die "patched source tree is stale (patch set changed) -- rerun with --clean"
    fi
    [ "$stamped" = "$sig" ] && return 0

    for f in "${files[@]}"; do
        bst_info "applying patch: ${f#"$BST_ROOT"/}"
        if command -v git >/dev/null 2>&1; then
            (cd "$src" && git apply -p1 --whitespace=nowarn "$f") || \
                (cd "$src" && patch -p1 -N -i "$f") || bst_die "patch failed: $f"
        else
            (cd "$src" && patch -p1 -N -i "$f") || bst_die "patch failed: $f"
        fi
    done
    echo "$sig" > "$src/.bst-patches"
    bst_info "patches applied: ${#files[@]}"
}

# ---------------------------------------------------------------------------
# path helpers
# ---------------------------------------------------------------------------
bst_win_path() { # native (Windows) path for MSVC tools; identity elsewhere
    if [ "$SITE_FAMILY" = windows ]; then
        cygpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

# ---------------------------------------------------------------------------
# staging
# ---------------------------------------------------------------------------
bst_stage_dir() { # <lib> <triple> -> dist path
    echo "$BST_ROOT/dist/$1/$2"
}

bst_prepare_stage() { # <lib> <triple>: wipe and create the staged prefix
    BST_DIST="$(bst_stage_dir "$1" "$2")"
    rm -rf "$BST_DIST"
    mkdir -p "$BST_DIST"
}

bst_write_build_info() { # <lib> <version> <variants> <extra>
    local f="$BST_DIST/BUILD-INFO.txt"
    {
        echo "lib:        $1"
        echo "version:    $2"
        echo "site:       $SITE"
        echo "triple:     $SITE_TRIPLE"
        echo "variants:   $3"
        echo "host:       $(uname -s) $(uname -m)"
        echo "cc:         ${CC:-?}"
        local cc1="${CC:-}"; cc1="${cc1%% *}"
        if [ -n "$cc1" ] && command -v "$cc1" >/dev/null 2>&1; then
            "$cc1" --version 2>/dev/null | head -1 || true
        fi
        echo "tarball:    ${BST_TARBALL:-}"
        echo "tarball sha256: $(bst_sha256_of "${BST_TARBALL:-/dev/null}" 2>/dev/null || echo '?')"
        echo "built by:   bst $BST_VERSION (scripts/build.sh ${4:-})"
        echo "built at:   $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } >"$f"
}

# ---------------------------------------------------------------------------
# results summary
# ---------------------------------------------------------------------------
bst_list_dist() {
    [ -d "$BST_DIST" ] || return 0
    find "$BST_DIST" -type f \( -name '*.a' -o -name '*.lib' -o -name '*.so' -o -name '*.so.*' -o -name '*.dylib' -o -name '*.dll' \) 2>/dev/null | sort
}
