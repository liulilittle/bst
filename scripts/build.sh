#!/usr/bin/env bash
# bst entry point: build one library for one site.
#
# One command, no research:  scripts/build.sh <lib> --site <site>
#
# Examples:
#   scripts/build.sh openssl                      # this host's default site
#   scripts/build.sh jemalloc --site linux-aarch64
#   scripts/build.sh liburing --site linux-x86_64 --test
#   scripts/build.sh openssl --site windows-msvc-x64    # via scripts/build.ps1
#
# Options:
#   --site <site>       target site (default: this host; see ci/site-matrix.env)
#   --version <v>       upstream version (default per lib, see ci/versions.env)
#   --variant <v>       static | shared | both              (default: static)
#   --test              also run the upstream test suite
#   --clean             wipe this lib's build dir + staged dist first
#   --jobs <n>          parallelism (default: all cores)
#   --skip-smoke        skip the consumer smoke test
#   --list-sites        print the sites supported for <lib> and exit
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

LIB=""; SITE=""; VERSION=""; VARIANT="static"
RUN_TEST=0; CLEAN=0; JOBS=""; SKIP_SMOKE=0; LIST_SITES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --site)       SITE="${2:-}"; shift 2 ;;
        --version)    VERSION="${2:-}"; shift 2 ;;
        --variant)    VARIANT="${2:-}"; shift 2 ;;
        --test)       RUN_TEST=1; shift ;;
        --clean)      CLEAN=1; shift ;;
        --jobs)       JOBS="${2:-}"; shift 2 ;;
        --skip-smoke) SKIP_SMOKE=1; shift ;;
        --list-sites) LIST_SITES=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        -*)           bst_die "unknown option '$1' (see --help)" ;;
        *)
            if [ -z "$LIB" ]; then LIB="$1"; else bst_die "unexpected argument '$1'"; fi
            shift
            ;;
    esac
done

[ -n "$LIB" ] || { usage >&2; exit 2; }
case "$LIB" in
    openssl|jemalloc|liburing) ;;
    *) bst_die "unknown library '$LIB' (known: openssl jemalloc liburing)" ;;
esac
[ -f "$ROOT/scripts/lib/recipes/$LIB.sh" ] || bst_die "recipe missing: scripts/lib/recipes/$LIB.sh"

if [ "$LIST_SITES" -eq 1 ]; then
    bst_sites_for_lib "$LIB"
    exit 0
fi

[ -n "$SITE" ] || SITE="$(bst_host_site)"
[ -n "$SITE" ] || bst_die "cannot auto-detect a site for this host; pass --site (see ci/site-matrix.env)"

site_info "$SITE"
site_supports_lib "$LIB" || bst_die "site '$SITE' does not support '$LIB' (supported here: $SITE_LIBS)"
if ! bst_host_accepts_site "$SITE_FAMILY"; then
    bst_die "host family '$(bst_host_family)' cannot build site '$SITE'
  policy: Windows host -> Windows sites; Linux/WSL host -> Linux + Android; macOS host -> macOS
  on Windows run scripts/build.ps1 (it delegates WSL-capable sites through WSL automatically)"
fi

case "$VARIANT" in
    static|shared|both) ;;
    *) bst_die "--variant must be one of: static shared both" ;;
esac

[ -n "$VERSION" ] || VERSION="$(bst_default_version "$LIB")"
[ -n "$VERSION" ] || bst_die "no default version for '$LIB'; pass --version <v>"

JOBS="${JOBS:-$(bst_nproc)}"
export BST_JOBS="$JOBS" BST_TEST="$RUN_TEST" BST_SKIP_SMOKE="$SKIP_SMOKE"

mkdir -p "$ROOT/ci-logs"
LOG="$ROOT/ci-logs/${LIB}-${SITE}.log"
exec > >(tee "$LOG") 2>&1

bst_info "bst $BST_VERSION -- $LIB $VERSION -- site $SITE ($SITE_TRIPLE) -- variant $VARIANT -- jobs $JOBS"
bst_info "build dir: $BST_BUILD"
bst_info "cache dir: $BST_CACHE"

if [ "$CLEAN" -eq 1 ]; then
    bst_info "clean: removing .build/$LIB and dist/$LIB/$SITE_TRIPLE"
    rm -rf "$BST_BUILD/$LIB" "$(bst_stage_dir "$LIB" "$SITE_TRIPLE")"
fi

resolve_toolchain
resolve_emulator

# shellcheck source=/dev/null
. "$ROOT/scripts/lib/recipes/$LIB.sh"

bst_fetch "$LIB" "$VERSION"
bst_prepare_stage "$LIB" "$SITE_TRIPLE"

case "$VARIANT" in
    both) VARIANTS="static shared" ;;
    *)    VARIANTS="$VARIANT" ;;
esac

for v in $VARIANTS; do
    export BST_VARIANT="$v"
    BST_BUILD_DIR="$BST_BUILD/$LIB/$SITE-$v"
    export BST_BUILD_DIR
    [ "$CLEAN" -eq 1 ] && rm -rf "$BST_BUILD_DIR"
    mkdir -p "$BST_BUILD_DIR"

    bst_info "== [$LIB $SITE $v] configure =="
    recipe_configure
    bst_info "== [$LIB $SITE $v] build =="
    recipe_build
    bst_info "== [$LIB $SITE $v] install =="
    recipe_install
done

if [ "$RUN_TEST" -eq 1 ] && command -v recipe_test >/dev/null 2>&1; then
    bst_info "== [$LIB $SITE] upstream test suite =="
    recipe_test
fi

if [ "$SKIP_SMOKE" -eq 0 ] && command -v recipe_smoke >/dev/null 2>&1; then
    bst_info "== [$LIB $SITE] smoke test =="
    recipe_smoke
fi

bst_write_build_info "$LIB" "$VERSION" "$VARIANTS" "--site $SITE --variant $VARIANT"

bst_info "artifacts:"
bst_list_dist | sed 's/^/  /'
bst_info "done: $LIB $VERSION -> dist/$LIB/$SITE_TRIPLE  (log: ci-logs/${LIB}-${SITE}.log)"
