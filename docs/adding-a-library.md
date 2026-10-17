# Adding a library to bst

> [中文](adding-a-library.zh-CN.md) | English

Adding the next hard-to-build library is a checklist: one recipe file, rows
in two tables, a smoke test, CI matrix rows and doc updates. The framework
(entry points, site resolution, download/verify, staging, logging) is
already done.

## The recipe contract

A library lives in `scripts/lib/recipes/<lib>.sh` and implements up to five
functions. The framework calls them in order; every one runs with the site
context already resolved.

| Function | Required | Purpose |
| --- | --- | --- |
| `recipe_configure` | yes | run the upstream configure for `$BST_VARIANT` |
| `recipe_build` | yes | compile |
| `recipe_install` | yes | install into `$BST_DIST` (the staged prefix) |
| `recipe_test` | no | upstream test suite (called only with `--test`) |
| `recipe_smoke` | recommended | compile+link+run the consumer smoke against `$BST_DIST` |

### Variables provided

| Variable | Meaning |
| --- | --- |
| `BST_SRC` | extracted (and patched) upstream source tree |
| `BST_BUILD_DIR` | this variant's build directory (`--clean` wipes it) |
| `BST_DIST` | staged prefix being produced (`dist/<lib>/<triple>`) |
| `BST_VARIANT` | `static` or `shared` |
| `BST_JOBS` | parallelism |
| `BST_TEST` | `1` when `--test` was requested |
| `SITE`, `SITE_TRIPLE`, `SITE_FAMILY`, `SITE_CROSS`, `SITE_EMU` | site row facts |
| `CC`, `CXX`, `AR`, `RANLIB`, `STRIP` | toolchain for the site |
| `SITE_SYSROOT` | cross sysroot (empty for native) |

### Helpers provided (scripts/lib/common.sh)

| Helper | Use |
| --- | --- |
| `bst_die "$msg"` / `bst_warn` / `bst_info` | fail closed / warn / log |
| `bst_require_cmd <cmd> <install hint>` | actionable prerequisite checks |
| `bst_run_exe <exe>` | run through `qemu-user -L $SITE_SYSROOT` on cross sites |
| `bst_win_path <path>` | Windows path for MSVC tools, identity elsewhere |
| `bst_ndk_root` | validated NDK root (env `ANDROID_NDK` or the fetched copy) |
| `site_is_cross` | true for cross sites |
| `bst_prepare_stage` / `bst_list_dist` | used by the framework itself |

## Checklist

1. **Recipe**: create `scripts/lib/recipes/<lib>.sh`. Branch on
   `$SITE_FAMILY` where a platform needs different handling (see
   `openssl.sh` for Configure targets, `jemalloc.sh` for
   autotools-vs-MSVC, `liburing.sh` for a Linux-only tool).
2. **Site table**: add the library name to the `libs` column of every site
   in `ci/site-matrix.env` that upstream supports. Unsupported combinations
   stay absent — the entry point refuses them with a clear message.
3. **Versions**: `scripts/pin.sh <lib> <version> --update-default` appends
   the source row (URL + sha256) and sets the default. Add the
   `_DEFAULT_VERSION` line if `pin.sh` did not.
4. **Smoke test**: `tests/smoke/<lib>_smoke.c` — a tiny program that links
   against the staged artifacts and proves the library actually works
   (e.g. a known-answer digest for openssl). Call it from `recipe_smoke`.
5. **CI matrices**: add rows to `.github/workflows/ci.yml` and
   `release.yml` for the new library (matrices are hand-written by design;
   `ci/check-workflows.sh` fails when they drift from the site table).
6. **Docs**: add the library to the README table, the tests table in
   `docs/building.md`, and the matrix in `docs/platforms.md` (and the
   `.zh-CN.md` mirrors).
7. **Verify**: `scripts/tests/unit.sh`, then one native build with
   `--test`, then a cross build (smoke runs under qemu), then push and let
   CI take it from there.

## Minimal skeleton

```bash
# shellcheck shell=bash
# mylib recipe.

recipe_configure() {
    case "$SITE_FAMILY" in
        windows) bst_die "mylib: MSVC support not wired yet" ;;
    esac
    local args=(--prefix="$BST_DIST")
    case "$BST_VARIANT" in
        static) args+=(--disable-shared) ;;
        shared) args+=(--enable-shared) ;;
    esac
    site_is_cross && args+=(--host="$SITE_TRIPLE")
    ( cd "$BST_BUILD_DIR" && CC="$CC" "$BST_SRC/configure" "${args[@]}" ) \
        || bst_die "mylib configure failed"
}

recipe_build() {
    ( cd "$BST_BUILD_DIR" && make -j"$BST_JOBS" ) || bst_die "mylib build failed"
}

recipe_install() {
    ( cd "$BST_BUILD_DIR" && make install ) || bst_die "mylib install failed"
}

recipe_smoke() {
    local exe="$BST_BUILD_DIR/smoke-mylib"
    "$CC" -I"$BST_DIST/include" "$BST_ROOT/tests/smoke/mylib_smoke.c" \
        "$BST_DIST/lib/libmylib.a" -o "$exe" || bst_die "mylib smoke link failed"
    bst_run_exe "$exe" || bst_die "mylib smoke run failed"
}
```

## Rules that keep it reliable

- Fail closed: any unexpected state is `bst_die`, never a silent skip.
- Never patch tests to hide failures; patches change build behavior only
  (see `patches/README.md`).
- Keep the site table the single source of truth; do not invent site keys
  inside recipes.
- The smoke test is the contract with consumers: it links exactly like the
  docs tell users to link.
