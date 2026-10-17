# shellcheck shell=bash
# openssl recipe.
# One Configure target per site, out-of-source builds (supported upstream),
# install_sw for libs+apps+headers, upstream test suite where runnable.

BST_PERL="${BST_PERL:-perl}"
BST_NASM="${BST_NASM:-nasm}"

openssl_target() {
    case "$SITE" in
        linux-x86_64|linux-x86_64-clang) echo linux-x86_64 ;;
        linux-aarch64)   echo linux-aarch64 ;;
        linux-armv7)     echo linux-armv4 ;;
        linux-riscv64)   echo linux64-riscv64 ;;
        linux-ppc64le)   echo linux-ppc64le ;;
        linux-s390x)     echo linux64-s390x ;;
        linux-i686)      echo linux-x86 ;;
        windows-msvc-x64)    echo VC-WIN64A ;;
        windows-msvc-x86)    echo VC-WIN32 ;;
        windows-msvc-arm64)  echo VC-WIN64-ARM ;;
        macos-arm64)     echo darwin64-arm64-cc ;;
        macos-x64)       echo darwin64-x86_64-cc ;;
        android-arm64-v8a)   echo android-arm64 ;;
        android-armeabi-v7a) echo android-arm ;;
        android-x86_64)      echo android-x86_64 ;;
        android-x86)         echo android-x86 ;;
        *) echo "" ;;
    esac
}

recipe_configure() {
    local target
    target="$(openssl_target)"
    [ -n "$target" ] || bst_die "no openssl Configure target for site '$SITE'"
    bst_require_cmd "$BST_PERL" "install Perl (Windows: choco install strawberryperl / winget install StrawberryPerl.StrawberryPerl; Debian: apt-get install perl)"

    local cfg=(--prefix="$(bst_win_path "$BST_DIST")"
               --openssldir="$(bst_win_path "$BST_DIST/ssl")"
               --libdir=lib)
    case "$BST_VARIANT" in
        static) cfg+=(no-shared) ;;
        shared) cfg+=(shared) ;;
    esac
    # Skip building the (large) test binaries unless tests were requested.
    [ "$BST_TEST" -eq 1 ] || cfg+=(no-tests)

    case "$SITE_FAMILY" in
        windows)
            case "$SITE" in
                windows-msvc-x64|windows-msvc-x86)
                    bst_require_cmd "$BST_NASM" "install NASM: choco install nasm (reopen the shell afterwards)" ;;
            esac
            ;;
        android)
            local ndk
            ndk="$(bst_ndk_root)"
            export ANDROID_NDK_ROOT="$ndk"
            PATH="$ndk/toolchains/llvm/prebuilt/$(bst_ndk_host_tag)/bin:$PATH"
            export PATH
            cfg+=(-D__ANDROID_API__="$BST_ANDROID_API")
            ;;
        linux*)
            if site_is_cross; then
                # Some linux-* targets already bake in a cross CC; passing
                # --cross-compile-prefix on top of those double-prefixes the
                # compiler name.  Setting CC/CXX explicitly is unambiguous.
                cfg+=("CC=$CC" "CXX=$CXX")
            fi
            case "$SITE" in
                # armv7 hard-float: the linux-armv4 target implies no FPU, so
                # pin the arch + FPU + float ABI explicitly.
                linux-armv7) cfg+=(-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard) ;;
            esac
            ;;
        macos)
            # The darwin64-<arch>-cc targets already carry the right -arch;
            # passing -arch here makes Configure treat the flag's value as a
            # second target.
            ;;
    esac

    bst_info "openssl Configure target: $target ${cfg[*]}"
    ( cd "$BST_BUILD_DIR" && "$BST_PERL" "$BST_SRC/Configure" "$target" "${cfg[@]}" ) \
        || bst_die "openssl Configure failed"
}

recipe_build() {
    case "$SITE_FAMILY" in
        windows) ( cd "$BST_BUILD_DIR" && bst_msvc_run nmake /NOLOGO ) || bst_die "openssl nmake failed" ;;
        *)       ( cd "$BST_BUILD_DIR" && make -j"$BST_JOBS" ) || bst_die "openssl make failed" ;;
    esac
}

recipe_install() {
    case "$SITE_FAMILY" in
        windows) ( cd "$BST_BUILD_DIR" && bst_msvc_run nmake /NOLOGO install_sw ) || bst_die "openssl install_sw failed" ;;
        *)       ( cd "$BST_BUILD_DIR" && make install_sw ) || bst_die "openssl install_sw failed" ;;
    esac
}

recipe_test() {
    case "$SITE_FAMILY" in
        windows)
            ( cd "$BST_BUILD_DIR" && bst_msvc_run nmake /NOLOGO test ) || bst_die "openssl tests failed"
            ;;
        *)
            if [ -n "${BST_EMU:-}" ]; then
                bst_warn "openssl: upstream tests are skipped on cross sites (the perl harness is not qemu-capable here); smoke covers link+run"
                return 0
            fi
            ( cd "$BST_BUILD_DIR" && make test HARNESS_JOBS="$BST_JOBS" ) || bst_die "openssl tests failed"
            ;;
    esac
}

recipe_smoke() {
    local src="$BST_ROOT/tests/smoke/openssl_smoke.c"
    local exe="$BST_BUILD_DIR/smoke-openssl"
    [ -f "$src" ] || bst_die "missing smoke source: $src"
    case "$SITE_FAMILY" in
        windows)
            ( cd "$BST_BUILD_DIR" && bst_msvc_run cl /nologo \
                "/I$(bst_win_path "$BST_DIST")\\include" \
                "$(bst_win_path "$src")" /Fe:"smoke.exe" /link \
                "/LIBPATH:$(bst_win_path "$BST_DIST")\\lib" \
                libssl.lib libcrypto.lib ws2_32.lib crypt32.lib advapi32.lib user32.lib gdi32.lib ) \
                || bst_die "openssl smoke build failed"
            ./smoke.exe || bst_die "openssl smoke run failed"
            ;;
        *)
            local link
            if [ "$SITE_FAMILY" = android ]; then
                # bionic: pthread/dl live inside libc; no -lpthread/-ldl stubs
                if [ -f "$BST_DIST/lib/libssl.a" ]; then
                    link="$BST_DIST/lib/libssl.a $BST_DIST/lib/libcrypto.a"
                else
                    link="-L$BST_DIST/lib -lssl -lcrypto"
                fi
            elif [ -f "$BST_DIST/lib/libssl.a" ]; then
                link="$BST_DIST/lib/libssl.a $BST_DIST/lib/libcrypto.a -ldl -lpthread"
            else
                link="-L$BST_DIST/lib -Wl,-rpath,$BST_DIST/lib -lssl -lcrypto -ldl -lpthread"
            fi
            # shellcheck disable=SC2086
            "$CC" -I"$BST_DIST/include" "$src" $link -o "$exe" \
                || bst_die "openssl smoke link failed"
            if [ "$SITE_FAMILY" = android ]; then
                bst_info "android: smoke compiled+linked OK (no device runner attached; run step skipped)"
                return 0
            fi
            bst_run_exe "$exe" || bst_die "openssl smoke run failed"
            ;;
    esac
}
