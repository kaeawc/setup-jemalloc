/*
 * zone_check  (issue #32, macOS)
 *
 * Prints the name of the malloc zone that served a normal malloc() allocation.
 * Run without jemalloc it shows the system default zone; run with jemalloc
 * inserted (DYLD_INSERT_LIBRARIES + MallocNanoZone=0) it must show jemalloc's
 * zone instead — proving jemalloc actually replaced the process allocator.
 *
 * This is a non-restricted, self-built binary, so SIP does not strip the
 * DYLD_* variables when it is launched.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <malloc/malloc.h>

int main(void) {
    void *p = malloc(4096);
    if (!p) {
        fprintf(stderr, "malloc failed\n");
        return 2;
    }
    memset(p, 0xAB, 4096);

    malloc_zone_t *z = malloc_zone_from_ptr(p);
    const char *name = z ? malloc_get_zone_name(z) : NULL;
    printf("zone=%s\n", name ? name : "(unknown)");

    free(p);
    return 0;
}
