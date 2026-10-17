# patches/

Optional upstream patches, applied automatically after the tarball is
extracted and verified.  This is the supported way to keep a library
buildable when upstream needs a small fix (build scripts, configuration or
source code) — the alternative, editing a vendored copy by hand, is not.

Layout:

    patches/<lib>/<version>/*.patch    applies only to that exact version
    patches/<lib>/*.patch              applies to every version

Rules:

- Files are applied in sorted filename order; use a numeric prefix
  (`0001-...`, `0002-...`) to control the order.
- Patches are applied with `git apply -p1` (GNU `patch -p1` as fallback),
  so they must be `-p1` unified diffs generated from the library root
  (e.g. `git diff` inside the extracted tarball or a git checkout).
- The applied patch set is stamped into the extracted source tree.  If you
  add, remove or edit a patch afterwards, rerun the build with `--clean`.
- Never patch tests to make a failure disappear; patches must keep the
  library's behavior intact.

Example:

    git clone --depth 1 --branch 5.4.0 https://github.com/jemalloc/jemalloc /tmp/jemalloc
    cd /tmp/jemalloc && git checkout -b tmp && $EDITOR <files>
    git diff > <bst>/patches/jemalloc/5.4.0/0001-<what>.patch
