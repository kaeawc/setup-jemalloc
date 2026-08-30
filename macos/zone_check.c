/*
 * zone_check  (issue #32, macOS)
 *
 * Determines whether jemalloc actually SERVES the process's malloc when it is
 * inserted via DYLD_INSERT_LIBRARIES — not merely whether it is loaded.
 *
 * Signals printed:
 *   zone=...            the malloc zone that owns a normal malloc() block
 *                       (jemalloc's zone override, when it works).
 *   jemalloc_loaded=... whether jemalloc's mallctl symbol resolves at all.
 *   served_by_jemalloc=yes|no
 *                       DEFINITIVE: allocate 1 MiB and check jemalloc's own
 *                       stats.allocated actually grew by ~that much. This is
 *                       true only if malloc() was really routed to jemalloc.
 *
 * Self-built, non-restricted binary, so SIP does not strip DYLD_*.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dlfcn.h>
#include <malloc/malloc.h>

typedef int (*mallctl_t)(const char *, void *, size_t *, void *, size_t);

int main(void) {
    void *warm = malloc(4096);
    malloc_zone_t *z = malloc_zone_from_ptr(warm);
    const char *zname = z ? malloc_get_zone_name(z) : NULL;
    printf("zone=%s\n", zname ? zname : "(unknown)");
    free(warm);

    /* jemalloc may be prefixed (je_mallctl) or unprefixed (mallctl). */
    mallctl_t mc = (mallctl_t)dlsym(RTLD_DEFAULT, "je_mallctl");
    if (!mc) mc = (mallctl_t)dlsym(RTLD_DEFAULT, "mallctl");
    if (!mc) {
        printf("jemalloc_loaded=no\n");
        printf("served_by_jemalloc=no\n");
        return 0;
    }
    printf("jemalloc_loaded=yes\n");

    uint64_t epoch = 1;
    size_t szu = sizeof(size_t);
    size_t before = 0, after = 0;
    mc("epoch", NULL, NULL, &epoch, sizeof(epoch));
    if (mc("stats.allocated", &before, &szu, NULL, 0) != 0) {
        printf("served_by_jemalloc=unknown (stats unavailable)\n");
        return 0;
    }

    const size_t BIG = 1u << 20; /* 1 MiB */
    void *p = malloc(BIG);
    if (!p) { printf("served_by_jemalloc=no (malloc failed)\n"); return 0; }
    memset(p, 0x5a, BIG);

    epoch = 1;
    mc("epoch", NULL, NULL, &epoch, sizeof(epoch));
    mc("stats.allocated", &after, &szu, NULL, 0);
    free(p);

    long long delta = (long long)after - (long long)before;
    printf("jemalloc_stats_delta=%lld\n", delta);
    /* If jemalloc served the 1 MiB malloc, allocated grows by at least ~half. */
    printf("served_by_jemalloc=%s\n", (delta >= (long long)(BIG / 2)) ? "yes" : "no");
    return 0;
}
