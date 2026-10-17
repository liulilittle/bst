# shellcheck shell=bash
# jemalloc recipe.
#   - Linux/macOS/Android: autotools (release tarball ships a ready configure)
#   - Windows x64/x86: the official MSVC project files (msvc/jemalloc_vc2022.sln)
#     after header generation with CC=cl; ARM64 is not supported upstream and
#     fails closed at the site check.

recipe_configure() {
    case "$SITE_FAMILY" in
        windows) jemalloc_configure_windows ;;
        *)       jemalloc_configure_unix ;;
    esac
}

jemalloc_configure_unix() {
    bst_require_cmd make "apt-get install make (or: xcode-select --install on macOS)"
    local args=(--prefix="$BST_DIST" --libdir="$BST_DIST/lib")
    case "$BST_VARIANT" in
        static) args+=(--enable-static --disable-shared) ;;
        shared) args+=(--disable-static --enable-shared) ;;
    esac
    case "$SITE_FAMILY" in
        android) args+=(--host="$SITE_TRIPLE") ;;
        *) site_is_cross && args+=(--host="$SITE_TRIPLE") ;;
    esac
    local extra_cflags=""
    if [ "$SITE_FAMILY" = macos ]; then
        # allow macos-x64 to build on an arm64 host (and vice versa)
        extra_cflags="-arch $SITE_DARWIN_ARCH"
    fi
    if [ "$SITE_FAMILY" = android ]; then
        # bionic declares malloc_usable_size with __attribute__((nothrow)),
        # which conflicts with jemalloc's C++ operator-override translation
        # unit (exception specification mismatch).  C++ integration is
        # meaningless on Android (bionic supplies operator new/delete), so
        # disable it there.
        args+=(--disable-cxx)
    fi
    ( cd "$BST_BUILD_DIR" && \
      CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      CFLAGS="$extra_cflags" CXXFLAGS="$extra_cflags" \
      "$BST_SRC/configure" "${args[@]}" ) || bst_die "jemalloc configure failed"
}

jemalloc_configure_windows() {
    local sh="${BST_SH:-sh}"
    bst_require_cmd "$sh" "Git for Windows (provides sh.exe) or MSYS2"
    command -v cl >/dev/null 2>&1 || bst_die "cl.exe not in PATH -- run through scripts/build.ps1"
    # Generate the headers the MSVC project compiles against (once per source
    # tree).  Only the generated include tree matters here; the Makefile that
    # configure emits is not used.
    if [ ! -f "$BST_SRC/.bst-win-headers" ]; then
        ( cd "$BST_SRC" && CC=cl "$sh" ./configure --disable-shared ) \
            || bst_die "jemalloc Windows header generation failed (CC=cl ./configure)"
        touch "$BST_SRC/.bst-win-headers"
    fi
}

jemalloc_msvc_config() { # -> Release-static | Release
    case "$BST_VARIANT" in
        shared) echo "Release" ;;
        *)      echo "Release-static" ;;
    esac
}

jemalloc_msvc_platform() {
    case "$SITE" in
        windows-msvc-x64) echo "x64" ;;
        windows-msvc-x86) echo "Win32" ;;
        *) bst_die "no MSVC project platform for '$SITE' (jemalloc ships x64/x86 only)" ;;
    esac
}

recipe_build() {
    case "$SITE_FAMILY" in
        windows)
            local cfg plat mb mb_exe
            cfg="$(jemalloc_msvc_config)"
            plat="$(jemalloc_msvc_platform)"
            mb="${BST_MSBUILD:-msbuild}"
            mb_exe="$(command -v cygpath >/dev/null 2>&1 && cygpath -u "$mb" 2>/dev/null || echo "$mb")"
            [ -x "$mb_exe" ] || command -v "$mb" >/dev/null 2>&1 || \
                bst_die "missing MSBuild -- run through scripts/build.ps1 (loads the Visual Studio environment)"
            ( cd "$BST_SRC/msvc" && bst_msvc_run "$mb_exe" jemalloc_vc2022.sln /nologo /m:"$BST_JOBS" \
                /p:Configuration="$cfg" /p:Platform="$plat" ) || bst_die "jemalloc msbuild failed"
            ;;
        *)
            ( cd "$BST_BUILD_DIR" && make -j"$BST_JOBS" ) || bst_die "jemalloc build failed"
            ;;
    esac
}

recipe_install() {
    case "$SITE_FAMILY" in
        windows) jemalloc_install_windows ;;
        *) ( cd "$BST_BUILD_DIR" && make install ) || bst_die "jemalloc install failed" ;;
    esac
}

jemalloc_install_windows() {
    local plat cfg out
    plat="$(jemalloc_msvc_platform)"
    cfg="$(jemalloc_msvc_config)"
    out="$BST_SRC/msvc/projects/vc2022/$plat/$cfg"
    [ -d "$out" ] || bst_die "expected MSVC output dir missing: $out"
    mkdir -p "$BST_DIST/lib" "$BST_DIST/bin" "$BST_DIST/include"
    cp -f "$out"/*.lib "$BST_DIST/lib/" 2>/dev/null || true
    cp -f "$out"/*.dll "$BST_DIST/bin/" 2>/dev/null || true
    cp -f "$out"/*.pdb "$BST_DIST/lib/" 2>/dev/null || true
    # normalize the library name so consumers always link "jemalloc.lib"
    local bst_lib
    for bst_lib in "$BST_DIST/lib"/jemalloc*.lib; do
        [ -e "$bst_lib" ] || continue
        case "$bst_lib" in *-static*|*jemalloc.lib) cp -f "$bst_lib" "$BST_DIST/lib/jemalloc.lib" ;; esac
    done
    cp -r "$BST_SRC/include/jemalloc" "$BST_DIST/include/"
    [ -d "$BST_SRC/include/msvc_compat" ] && cp -r "$BST_SRC/include/msvc_compat" "$BST_DIST/include/"
    return 0
}

recipe_test() {
    case "$SITE_FAMILY" in
        windows)
            bst_warn "jemalloc: upstream test suite is not wired for MSVC in bst yet; smoke covers link+run"
            ;;
        *)
            if [ -n "${BST_EMU:-}" ]; then
                bst_warn "jemalloc: upstream tests are skipped on cross sites; smoke covers link+run"
                return 0
            fi
            ( cd "$BST_BUILD_DIR" && make check -j"$BST_JOBS" ) || bst_die "jemalloc make check failed"
            ;;
    esac
}

recipe_smoke() {
    local src="$BST_ROOT/tests/smoke/jemalloc_smoke.c"
    local exe="$BST_BUILD_DIR/smoke-jemalloc"
    [ -f "$src" ] || bst_die "missing smoke source: $src"
    case "$SITE_FAMILY" in
        windows)
            ( cd "$BST_BUILD_DIR" && bst_msvc_run cl /nologo "/I$(bst_win_path "$BST_DIST")\\include" \
                "/I$(bst_win_path "$BST_DIST")\\include\\msvc_compat" \
                "$(bst_win_path "$src")" /Fe:"smoke.exe" /link \
                "/LIBPATH:$(bst_win_path "$BST_DIST")\\lib" jemalloc.lib ) || bst_die "jemalloc smoke build failed"
            # a shared-variant smoke needs the DLL discoverable at run time
            if [ -d "$BST_DIST/bin" ]; then
                PATH="$(cygpath -u "$(bst_win_path "$BST_DIST")")/bin:$PATH"
                export PATH
            fi
            ( cd "$BST_BUILD_DIR" && ./smoke.exe ) || bst_die "jemalloc smoke run failed"
            ;;
        *)
            local link_libs="-lpthread -ldl" arch_flags=""
            [ "$SITE_FAMILY" = android ] && link_libs=""   # bionic: pthread/dl in libc
            [ "$SITE_FAMILY" = macos ] && arch_flags="-arch $SITE_DARWIN_ARCH"
            local link
            if [ -f "$BST_DIST/lib/libjemalloc.a" ]; then
                link="$BST_DIST/lib/libjemalloc.a"
            else
                link="-L$BST_DIST/lib -Wl,-rpath,$BST_DIST/lib -ljemalloc"
            fi
            # shellcheck disable=SC2086
            "$CC" $arch_flags -I"$BST_DIST/include" -I"$BST_DIST/include/msvc_compat" "$src" \
                $link $link_libs -o "$exe" \
                || bst_die "jemalloc smoke link failed"
            if [ "$SITE_FAMILY" = android ]; then
                bst_info "android: smoke compiled+linked OK (no device runner attached; run step skipped)"
                return 0
            fi
            bst_run_exe "$exe" || bst_die "jemalloc smoke run failed"
            ;;
    esac
}
