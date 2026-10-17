#!/usr/bin/env bash
# Stage one built (lib, site) as a distributable tarball.
#
# usage: scripts/ci/stage-dist.sh <lib> <site> [outdir]
#
# Produces:  <outdir>/bst-<lib>-<version>-<triple>.tar.gz   (default outdir: dist-out)
#            <outdir>/bst-<lib>-<version>-<triple>.tar.gz.sha256
# The tarball root is the triple directory (include/, lib/, bin/, BUILD-INFO.txt).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

[ $# -ge 2 ] || bst_die "usage: scripts/ci/stage-dist.sh <lib> <site> [outdir]"
LIB="$1"; SITE="$2"; OUTDIR="${3:-$ROOT/dist-out}"

site_info "$SITE"
DIST="$(bst_stage_dir "$LIB" "$SITE_TRIPLE")"
[ -d "$DIST" ] || bst_die "no staged output: $DIST (build first)"
[ -f "$DIST/BUILD-INFO.txt" ] || bst_die "missing BUILD-INFO.txt in $DIST"
VER="$(awk -F': *' '$1=="version"{print $2}' "$DIST/BUILD-INFO.txt")"
[ -n "$VER" ] || bst_die "cannot read version from $DIST/BUILD-INFO.txt"

mkdir -p "$OUTDIR"
NAME="bst-$LIB-$VER-$SITE_TRIPLE.tar.gz"
OUT="$OUTDIR/$NAME"
rm -f "$OUT"
tar -C "$(dirname "$DIST")" -czf "$OUT" "$(basename "$DIST")"
bst_sha256 "$OUT" | awk '{print $1}' >"$OUT.sha256"
bst_info "staged: $OUT"
bst_info "sha256: $(cat "$OUT.sha256")"
