#!/usr/bin/env bash
# Framework self-tests: everything that can be checked without compiling a
# library.  Run it after touching scripts/lib/common.sh or the site table.
#
# usage: bash scripts/tests/unit.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BST_ROOT="$ROOT"
. "$ROOT/scripts/lib/common.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
not() { fail=$((fail+1)); echo "FAIL - $1"; }

# --- site table -------------------------------------------------------------
n="$(bst_sites | wc -l)"
[ "$n" -ge 16 ] && ok "site table has $n sites" || not "site table has only $n sites"

for s in linux-x86_64 linux-aarch64 windows-msvc-x64 macos-arm64 android-arm64-v8a; do
    site_info "$s" 2>/dev/null && [ -n "$SITE_TRIPLE" ] && ok "site_info $s -> $SITE_TRIPLE" || not "site_info $s"
done

site_info linux-aarch64
[ "$SITE_CROSS" = "aarch64-linux-gnu-" ] && ok "cross prefix parsed" || not "cross prefix parsed ($SITE_CROSS)"
[ "$SITE_EMU" = "qemu-aarch64" ] && ok "emulator parsed" || not "emulator parsed ($SITE_EMU)"
site_info linux-x86_64
[ -z "$SITE_CROSS" ] && ok "native prefix empty" || not "native prefix empty ($SITE_CROSS)"

# bst_lib support matrix
site_info windows-msvc-arm64
site_supports_lib openssl && ok "windows-arm64 supports openssl" || not "windows-arm64 supports openssl"
site_supports_lib jemalloc && not "windows-arm64 must not claim jemalloc" || ok "windows-arm64 jemalloc correctly refused"
site_info linux-x86_64
site_supports_lib liburing && ok "linux-x86_64 supports liburing" || not "linux-x86_64 supports liburing"
site_info macos-arm64
site_supports_lib liburing && not "macos must not claim liburing" || ok "macos liburing correctly refused"

# host gate
bst_host_family >/dev/null && ok "host family detected: $(bst_host_family)" || not "host family"

# --- versions table ---------------------------------------------------------
for bst_lib in openssl jemalloc liburing; do
    v="$(bst_default_version "$bst_lib")"
    [ -n "$v" ] || { not "default version for $bst_lib"; continue; }
    row="$(bst_version_row "$bst_lib" "$v")"
    case "$row" in
        https://*"|"*) ok "version row $bst_lib $v pinned" ;;
        *) not "version row $bst_lib $v missing" ;;
    esac
done

# every bst_lib default must exist in the table with a 64-hex sha
while read -r bst_lib v; do
    row="$(bst_version_row "$bst_lib" "$v")"
    sha="${row#*|}"
    case "$sha" in
        *[!0-9a-f]*|"") not "$bst_lib $v sha256 format" ;;
        *) [ "${#sha}" -eq 64 ] && ok "$bst_lib $v sha256 format" || not "$bst_lib $v sha256 length ${#sha}" ;;
    esac
done <<EOF
$(for l in openssl jemalloc liburing; do echo "$l $(bst_default_version "$l")"; done)
EOF

# --- entry point wiring -----------------------------------------------------
bash "$ROOT/scripts/build.sh" --help >/dev/null 2>&1 && ok "build.sh --help" || not "build.sh --help"
out="$(bash "$ROOT/scripts/build.sh" liburing --list-sites 2>/dev/null)"
echo "$out" | grep -q '^linux-aarch64$' && ok "build.sh --list-sites" || not "build.sh --list-sites"
bash "$ROOT/scripts/build.sh" nope --site linux-x86_64 >/dev/null 2>&1 && not "unknown bst_lib must fail" || ok "unknown bst_lib rejected"
bash "$ROOT/scripts/build.sh" openssl --site not-a-site >/dev/null 2>&1 && not "unknown site must fail" || ok "unknown site rejected"
bash "$ROOT/scripts/build.sh" liburing --site macos-arm64 >/dev/null 2>&1 && not "liburing on macos must fail" || ok "liburing on macos rejected"

echo
echo "unit: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
