#!/usr/bin/env bash
# Single (lib, site) build + test driver.
#
# CI and local runs use this exact code path: the workflow YAML only installs
# dependencies and calls this script; nothing site-specific lives in YAML.
#
# usage: scripts/ci/build-test.sh <lib> <site> [build.sh options...]
#
# Defaults applied here:
#   - upstream tests are enabled on native Linux sites (they run for real);
#     cross sites run the smoke test instead.  Pass --test / --no-test to
#     force either way.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

[ $# -ge 2 ] || bst_die "usage: scripts/ci/build-test.sh <lib> <site> [build.sh options...]"
LIB="$1"; SITE="$2"; shift 2

site_info "$SITE"

EMU="$SITE_EMU"
case "$SITE_FAMILY" in
    linux|linux-clang)
        if [ -z "$EMU" ]; then
            # native linux: real upstream test suite is runnable
            set -- --test "$@"
        fi
        ;;
esac

echo "== build-test: $LIB / $SITE =="
exec "$ROOT/scripts/build.sh" "$LIB" --site "$SITE" "$@"
