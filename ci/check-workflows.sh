#!/usr/bin/env bash
# Static consistency check for the CI workflows.
#
# The authoritative site list lives in ci/site-matrix.env; the workflow YAML
# carries hand-written matrices (no YAML generation, no hidden magic).  This
# script fails when the two drift apart, and when a workflow stops driving the
# same scripts a human runs locally.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

WF="$ROOT/.github/workflows"
status=0
fail() { echo "check-workflows: FAIL: $*" >&2; status=1; }
note() { echo "check-workflows: $*"; }

[ -d "$WF" ] || { fail "no .github/workflows directory"; exit 1; }

# --- 1. every site in the table must appear in ci.yml ------------------------
for s in $(bst_sites); do
    grep -q -- "$s" "$WF/ci.yml" || fail "site '$s' is not referenced by ci.yml"
done

# --- 2. no unknown site-looking tokens in the workflows ----------------------
is_skippable_token() {
    case "$1" in
        # runner labels
        windows-2019|windows-2022|windows-2025) return 0 ;;
        macos-1[1-9]) return 0 ;;
        # job ids / workflow expressions / apt suffixes that share the shape
        android-ndk*) return 0 ;;
        linux-native|linux-cross) return 0 ;;
        *.result|*.outputs) return 0 ;;
        linux-gnu|linux-gnueabi*|linux-android*) return 0 ;;
    esac
    return 1
}
for f in "$WF"/*.yml; do
    [ -e "$f" ] || continue
    for tok in $(grep -oE '\b(linux|windows|macos|android)-[a-z0-9._-]+\b' "$f" | sort -u); do
        is_skippable_token "$tok" && continue
        ( site_info "$tok" >/dev/null 2>&1 ) || \
            fail "$(basename "$f"): token '$tok' looks like a site but is not in ci/site-matrix.env"
    done
done

# --- 3. workflows must drive the same entry point as humans ------------------
grep -q 'scripts/ci/build-test.sh' "$WF/ci.yml" || fail "ci.yml does not call scripts/ci/build-test.sh"
grep -q 'scripts/build.ps1' "$WF/ci.yml" || fail "ci.yml does not call scripts/build.ps1 (Windows jobs)"
grep -q 'scripts/ci/stage-dist.sh' "$WF/release.yml" || fail "release.yml does not call scripts/ci/stage-dist.sh"

# --- 4. every library referenced must exist as a recipe ----------------------
for lib in openssl jemalloc liburing; do
    [ -f "$ROOT/scripts/lib/recipes/$lib.sh" ] || fail "missing recipe: scripts/lib/recipes/$lib.sh"
done

if [ "$status" -eq 0 ]; then
    note "OK (sites=$(bst_sites | wc -l | tr -d ' '), workflows=$(ls "$WF"/*.yml 2>/dev/null | wc -l | tr -d ' '))"
fi
exit "$status"
