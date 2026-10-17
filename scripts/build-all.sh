#!/usr/bin/env bash
# Build every (lib, site) that this host can build, one at a time, through the
# same scripts/ci/build-test.sh driver CI uses.
#
# usage: scripts/build-all.sh [--lib <lib>] [--sites "<s1> <s2> ..."] [--keep-going] [build.sh options...]
#
#   --lib <lib>       restrict to one library
#   --sites "<list>"  restrict to these site keys (default: every site this
#                     host family can build)
#   --keep-going      continue after a failure (default: stop at the first)
#
# Extra options are forwarded to build.sh for every site (e.g. --test,
# --variant both).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

LIBS="openssl jemalloc liburing"
ONLY_SITES=""
KEEP_GOING=0
PASSTHROUGH=()

while [ $# -gt 0 ]; do
    case "$1" in
        --lib)        LIBS="${2:-}"; shift 2 ;;
        --sites)      ONLY_SITES="${2:-}"; shift 2 ;;
        --keep-going) KEEP_GOING=1; shift ;;
        *)            PASSTHROUGH+=("$1"); shift ;;
    esac
done

HF="$(bst_host_family)"
[ -n "$HF" ] || bst_die "unknown host family"

pass=0; fail=0; skip=0
results=()

for lib in $LIBS; do
    if [ -n "$ONLY_SITES" ]; then
        sites="$ONLY_SITES"
    else
        sites="$(bst_sites_for_lib "$lib")"
    fi
    for site in $sites; do
        site_info "$site"
        if ! bst_host_accepts_site "$SITE_FAMILY"; then
            results+=("$lib/$site: SKIP (foreign host family)")
            skip=$((skip + 1))
            continue
        fi
        if [ "$SITE_FAMILY" = android ]; then
            if [ -z "${ANDROID_NDK:-}" ] && [ ! -d "$BST_CACHE/ndk/android-ndk-r${BST_NDK_VERSION}" ]; then
                results+=("$lib/$site: SKIP (no NDK -- run scripts/setup-ndk.sh)")
                skip=$((skip + 1))
                continue
            fi
        fi
        if "$ROOT/scripts/ci/build-test.sh" "$lib" "$site" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}; then
            results+=("$lib/$site: PASS"); pass=$((pass + 1))
        else
            results+=("$lib/$site: FAIL"); fail=$((fail + 1))
            if [ "$KEEP_GOING" -eq 0 ]; then
                echo
                for r in "${results[@]}"; do printf '  %-48s %s\n' "${r%%:*}" "${r#*: }"; done
                bst_die "stopped at first failure (use --keep-going to continue)"
            fi
        fi
    done
done

echo
echo "== bst build-all summary =="
for r in "${results[@]}"; do printf '  %-48s %s\n' "${r%%:*}" "${r#*: }"; done
echo "pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ] || exit 1
exit 0
