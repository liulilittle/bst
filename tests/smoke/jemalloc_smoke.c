/* bst smoke test for jemalloc: link against the staged libraries, run, and
 * exercise the public API (including one mallctl call).
 *
 * bst builds jemalloc with the default (empty) symbol prefix on every site,
 * so the library exports the standard allocator names; that is also the
 * symbol set consumers link against when they use jemalloc as a malloc
 * replacement. */
#include <stdio.h>
#include <string.h>

#include <jemalloc/jemalloc.h>

int main(void) {
    unsigned narenas = 0;
    size_t sz = sizeof(narenas);
    size_t usable = 0;
    void *p = malloc(1234);

    if (p == NULL) {
        fprintf(stderr, "jemalloc smoke: malloc failed\n");
        return 10;
    }
    memset(p, 0xA5, 1234);
    usable = malloc_usable_size(p);
    free(p);
    if (usable < 1234) {
        fprintf(stderr, "jemalloc smoke: malloc_usable_size too small (%u)\n", (unsigned)usable);
        return 11;
    }
    if (mallctl("arenas.narenas", &narenas, &sz, NULL, 0) != 0) {
        fprintf(stderr, "jemalloc smoke: mallctl failed\n");
        return 12;
    }
    printf("jemalloc smoke ok: arenas=%u\n", narenas);
    return 0;
}
