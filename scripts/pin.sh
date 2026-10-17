#!/usr/bin/env bash
# Pin a new upstream version: download the official tarball, compute its
# sha256, and append the row to ci/versions.env.
#
# usage: scripts/pin.sh <openssl|jemalloc|liburing> <version> [--update-default]
#
#   --update-default  also bump the library's default version in versions.env
#
# This is the "library upgrade" path: pin once, then build normally
# (scripts/build.sh <lib> --version <v> ... or just rebuild after bumping the
# default).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

[ $# -ge 2 ] || bst_die "usage: scripts/pin.sh <openssl|jemalloc|liburing> <version> [--update-default]"
LIB="$1"; VER="$2"; shift 2
UPDATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --update-default) UPDATE=1; shift ;;
        *) bst_die "unknown option '$1'" ;;
    esac
done

case "$LIB" in
    openssl)  URL="https://github.com/openssl/openssl/releases/download/openssl-$VER/openssl-$VER.tar.gz" ;;
    jemalloc) URL="https://github.com/jemalloc/jemalloc/releases/download/$VER/jemalloc-$VER.tar.bz2" ;;
    liburing) URL="https://github.com/axboe/liburing/archive/refs/tags/liburing-$VER.tar.gz" ;;
    *) bst_die "unknown library '$LIB' (known: openssl jemalloc liburing)" ;;
esac

what="$(bst_version_row "$LIB" "$VER")"
if [ -n "$what" ]; then
    bst_info "$LIB $VER is already pinned: $what"
    exit 0
fi

FNAME="${URL##*/}"
mkdir -p "$BST_CACHE/src"
TARBALL="$BST_CACHE/src/$FNAME"
bst_info "downloading $URL"
curl -fsSL --retry 3 -o "$TARBALL.tmp" "$URL" || bst_die "download failed: $URL"
mv "$TARBALL.tmp" "$TARBALL"
SHA="$(bst_sha256_of "$TARBALL")"
bst_info "sha256($FNAME) = $SHA"

ROW="$LIB|$VER|$URL|$SHA"
grep -q "^$LIB|$VER|" "$ROOT/ci/versions.env" 2>/dev/null && bst_die "row already present (race?)"
printf '%s\n' "$ROW" >>"$ROOT/ci/versions.env"
bst_info "appended to ci/versions.env: $ROW"

if [ "$UPDATE" -eq 1 ]; then
    UP="$(echo "$LIB" | tr '[:lower:]' '[:upper:]')_DEFAULT_VERSION"
    if [ "$(uname -s)" = Darwin ]; then
        sed -i '' "s/^${UP}=.*/${UP}=${VER}/" "$ROOT/ci/versions.env"
    else
        sed -i "s/^${UP}=.*/${UP}=${VER}/" "$ROOT/ci/versions.env"
    fi
    bst_info "default version for $LIB is now $VER"
fi
