/*
 * alloc_test.exe  (issue #28)
 *
 * A tiny, allocator-agnostic workload: it just calls the standard CRT
 * malloc/calloc/realloc/free many times. When launched via jemalloc-run.exe,
 * the injected shim redirects these to jemalloc; run directly, it uses the CRT.
 * Either way it must exit cleanly (0), which is the corruption/crash guard.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    const int N = 2000;
    void **ptrs = (void **)malloc(sizeof(void *) * N);
    if (!ptrs) return 10;

    for (int i = 0; i < N; ++i) {
        size_t sz = (size_t)((i % 512) + 1) * 8;
        ptrs[i] = malloc(sz);
        if (!ptrs[i]) return 11;
        memset(ptrs[i], (i & 0xff), sz);
    }

    /* realloc half of them (grow) */
    for (int i = 0; i < N; i += 2) {
        size_t sz = (size_t)((i % 256) + 2) * 16;
        void *p = realloc(ptrs[i], sz);
        if (!p) return 12;
        ptrs[i] = p;
        memset(ptrs[i], 0x5a, sz);
    }

    /* a few calloc'd blocks, verify zeroed */
    for (int i = 0; i < 100; ++i) {
        size_t cnt = (size_t)(i + 1);
        unsigned char *c = (unsigned char *)calloc(cnt, 8);
        if (!c) return 13;
        for (size_t k = 0; k < cnt * 8; ++k) {
            if (c[k] != 0) return 14;
        }
        free(c);
    }

    for (int i = 0; i < N; ++i) {
        free(ptrs[i]);
    }
    free(ptrs);

    printf("alloc_test OK: %d allocations exercised\n", N);
    return 0;
}
