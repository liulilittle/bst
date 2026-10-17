# shellcheck shell=bash
# liburing recipe (Linux only -- io_uring is a Linux kernel interface).
# Builds with liburing's own configure script; static + shared libraries and
# the full header set land in dist/liburing/<triple>.

recipe_configure() {
    bst_require_cmd make "apt-get install make"
    ( cd "$BST_BUILD_DIR" && \
      "$BST_SRC/configure" \
        --prefix="$BST_DIST" \
        --includedir="$BST_DIST/include" \
        --libdir="$BST_DIST/lib" \
        --libdevdir="$BST_DIST/lib" \
        --cc="$CC" \
        --cxx="$CXX" \
    ) || bst_die "liburing configure failed"
}

recipe_build() {
    # "library" builds only src/ -- the default "all" target also builds the
    # test tree (and its BPF probes), which we only want when --test is given.
    ( cd "$BST_BUILD_DIR" && make -j"$BST_JOBS" library ) || bst_die "liburing build failed"
}

recipe_install() {
    # liburing always ships static + shared; --variant is accepted but the
    # install set is the same (documented in docs/building.md).
    ( cd "$BST_BUILD_DIR" && make install ) || bst_die "liburing install failed"
}

recipe_test() {
    if [ -n "${BST_EMU:-}" ]; then
        bst_warn "liburing: upstream tests are skipped on cross sites (qemu kernel-feature coverage is not equivalent); smoke covers link+run"
        return 0
    fi
    # The test tree is built in-source: liburing 2.15's test Makefile hardcodes
    # -I../src/include for the BPF probes, which only resolves in-tree.  Tests
    # never contribute to dist/, so a disposable source copy is the simplest
    # correct route.
    local tree="$BST_BUILD_DIR/test-tree"
    if [ ! -d "$tree" ]; then
        cp -a "$BST_SRC" "$tree" || bst_die "failed to copy source tree for tests"
    fi
    ( cd "$tree" && ./configure --cc="$CC" --cxx="$CXX" >/dev/null ) \
        || bst_die "liburing test-tree configure failed"
    if ! ( cd "$tree" && make -j"$BST_JOBS" ); then
        bst_die "liburing test build failed
  note: the cBPF tests (bpf_nops, bpf_cp) need a consistent libbpf + bpftool
  pair (libbpf >= 1.4, e.g. both from source); run scripts/setup.sh to
  provision one, or rerun with --no-test to skip the upstream suite"
    fi
    # Test selection: a curated sub-set of the upstream suite is the default
    # gate -- it is deterministic across kernels (the full suite contains
    # feature/stress tests whose outcome depends on the exact kernel build).
    # BST_LIBURING_TESTS=all runs the full suite; or pass an explicit list.
    local tests="${BST_LIBURING_TESTS:-curated}"
    case "$tests" in
        all)
            ( cd "$tree" && TEST_EXCLUDE="${BST_LIBURING_TEST_EXCLUDE:-}" TIMEOUT="${BST_LIBURING_TEST_TIMEOUT:-60}" make runtests ) \
                || bst_die "liburing runtests failed (full suite)"
            ;;
        curated)
            local list=""
            for t in nop nop32 nop-flags read-write pipe pipe-eof poll timeout \
                     timeout-new submit-and-wait submit-reuse cq-size cq-ready \
                     version statx mkdir unlink rename hardlink symlink xattr \
                     open-close fadvise fallocate fsync truncate futex sq-full \
                     sq-space_left single-issuer; do
                [ -f "$tree/test/$t.t" ] && list="$list $t.t"
            done
            [ -n "$list" ] || bst_die "curated test list is empty (test tree layout changed?)"
            bst_info "liburing: running curated suite ($(echo $list | wc -w) tests; BST_LIBURING_TESTS=all for everything)"
            # shellcheck disable=SC2086
            ( cd "$tree/test" && TEST_EXCLUDE="${BST_LIBURING_TEST_EXCLUDE:-}" TIMEOUT="${BST_LIBURING_TEST_TIMEOUT:-60}" ./runtests.sh $list ) \
                || bst_die "liburing curated runtests failed"
            ;;
        *)
            # shellcheck disable=SC2086
            ( cd "$tree/test" && TEST_EXCLUDE="${BST_LIBURING_TEST_EXCLUDE:-}" TIMEOUT="${BST_LIBURING_TEST_TIMEOUT:-60}" ./runtests.sh $tests ) \
                || bst_die "liburing runtests failed"
            ;;
    esac
}

recipe_smoke() {
    local src="$BST_ROOT/tests/smoke/liburing_smoke.c"
    local exe="$BST_BUILD_DIR/smoke-liburing"
    [ -f "$src" ] || bst_die "missing smoke source: $src"
    "$CC" -I"$BST_DIST/include" "$src" "$BST_DIST/lib/liburing.a" -o "$exe" \
        || bst_die "liburing smoke link failed"
    bst_run_exe "$exe" || bst_die "liburing smoke run failed"
}
