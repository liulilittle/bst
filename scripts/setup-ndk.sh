#!/usr/bin/env bash
# Fetch and verify the pinned Android NDK (Linux host tag) into .cache/ndk/.
# After this, android-* sites build with no further setup.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

[ "$(bst_host_family)" = linux ] || bst_die "the NDK fetch script targets Linux hosts (WSL included); macOS: install the NDK manually and set ANDROID_NDK"

NDK_URL="${BST_NDK_URL:-https://dl.google.com/android/repository/android-ndk-r${BST_NDK_VERSION}-linux.zip}"
# Pinned checksum of android-ndk-r27c-linux.zip (recorded when first fetched;
# the zip is immutable on dl.google.com).  Override for a different version.
NDK_SHA256="${BST_NDK_SHA256:-59c2f6dc96743b5daf5d1626684640b20a6bd2b1d85b13156b90333741bad5cc}"

DEST="$BST_CACHE/ndk"
ROOT_DIR="$DEST/android-ndk-r${BST_NDK_VERSION}"
if [ -d "$ROOT_DIR" ] && [ -f "$ROOT_DIR/source.properties" ]; then
    bst_info "NDK already present: $ROOT_DIR"
    exit 0
fi

mkdir -p "$DEST" "$BST_CACHE/src"
ZIP="$BST_CACHE/src/android-ndk-r${BST_NDK_VERSION}-linux.zip"
if [ ! -f "$ZIP" ] || ! unzip -l "$ZIP" >/dev/null 2>&1; then
    bst_info "downloading $NDK_URL"
    rm -f "$ZIP"
    # resume + retry all transient failures (HTTP/2 stream resets included)
    curl -fL -C - --retry 5 --retry-all-errors --retry-delay 2 \
         --speed-limit 1024 --speed-time 60 -o "$ZIP" "$NDK_URL" \
        || bst_die "NDK download failed: $NDK_URL"
fi
if [ -n "$NDK_SHA256" ]; then
    got="$(bst_sha256_of "$ZIP")"
    [ "$got" = "$NDK_SHA256" ] || bst_die "NDK sha256 mismatch: $got"
    bst_info "NDK sha256 ok"
else
    bst_info "NDK sha256 not pinned yet; recording: $(bst_sha256_of "$ZIP")"
fi

bst_info "extracting to $DEST"
( cd "$DEST" && rm -rf "android-ndk-r${BST_NDK_VERSION}" && unzip -q "$ZIP" ) || bst_die "NDK unzip failed"
[ -f "$ROOT_DIR/source.properties" ] || bst_die "NDK extraction looks wrong (no source.properties)"
rm -f "$ZIP"
bst_info "NDK ready: $ROOT_DIR"
