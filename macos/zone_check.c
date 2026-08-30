/*
 * zone_check  (issue #32, macOS)
 *
 * Detects whether jemalloc has actually taken over the process allocator when
 * inserted via DYLD_INSERT_LIBRARIES. Two independent signals:
 *   1. the malloc zone that served a normal malloc() (jemalloc's zone override), and
 *   2. dlsym(RTLD_DEFAULT, "mallctl") resolving + reporting jemalloc's version
 *      (only present when an unprefixed jemalloc is live in the process).
 *
 * This is a non-restricted, self-built binary, so SIP does not strip DYLD_*.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <malloc/malloc.h>

typedef int (*mallctl_t)(const char *, void *, size_t *, void *, size_t);

int main(void) {
    void *p = malloc(4096);
    if (!p) {
        fprintf(stderr, "malloc failed\n");
        return 2;
    }
    memset(p, 0xAB, 4096);

    malloc_zone_t *z = malloc_zone_from_ptr(p);
    const char *zname = z ? malloc_get_zone_name(z) : NULL;
    printf("zone=%s\n", zname ? zname : "(unknown)");

    /* Definitive check: is jemalloc's mallctl live in this process? */
    mallctl_t mc = (mallctl_t)dlsym(RTLD_DEFAULT, "mallctl");
    if (mc) {
        const char *ver = NULL;
        size_t sz = sizeof(ver);
        if (mc("version", &ver, &sz, NULL, 0) == 0 && ver) {
            printf("jemalloc_version=%s\n", ver);
        } else {
            printf("jemalloc_version=mallctl-present-but-failed\n");
        }
    } else {
        printf("jemalloc_version=absent\n");
    }

    free(p);
    return 0;
}
