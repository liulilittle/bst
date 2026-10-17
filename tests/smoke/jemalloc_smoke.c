/* bst smoke test for jemalloc: link against the staged libraries, run, and
 * exercise the public API (including one mallctl call).
 *
 * Symbol names differ per platform because bst follows jemalloc's own
 * defaults: the empty prefix on Linux/Android exports the standard names,
 * while Darwin and MSVC builds use the je_ prefix (the upstream default
 * there).  The shim macros below pick the right set. */
#include <stdio.h>
#include <string.h>

#include <jemalloc/jemalloc.h>

#if defined(__APPLE__) || defined(_MSC_VER)
#  define smoke_malloc  je_malloc
#  define smoke_free    je_free
#  define smoke_usable  je_malloc_usable_size
#  define smoke_mallctl je_mallctl
#else
#  define smoke_malloc  malloc
#  define smoke_free    free
#  define smoke_usable  malloc_usable_size
#  define smoke_mallctl mallctl
#endif

int main(void) {
    unsigned narenas = 0;
    size_t sz = sizeof(narenas);
    size_t usable = 0;
    void *p = smoke_malloc(1234);

    if (p == NULL) {
        fprintf(stderr, "jemalloc smoke: malloc failed\n");
        return 10;
    }
    memset(p, 0xA5, 1234);
    usable = smoke_usable(p);
    smoke_free(p);
    if (usable < 1234) {
        fprintf(stderr, "jemalloc smoke: usable size too small (%u)\n", (unsigned)usable);
        return 11;
    }
    if (smoke_mallctl("arenas.narenas", &narenas, &sz, NULL, 0) != 0) {
        fprintf(stderr, "jemalloc smoke: mallctl failed\n");
        return 12;
    }
    printf("jemalloc smoke ok: arenas=%u\n", narenas);
    return 0;
}
