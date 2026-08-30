/*
 * Phase 1 smoke test (issue #28): prove the built jemalloc DLL is a real,
 * loadable jemalloc that can allocate and free memory.
 *
 * Usage: smoke.exe <path-to-jemalloc-dll>
 * Exit 0 on success; non-zero with a message otherwise.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>

typedef void *(*malloc_fn)(size_t);
typedef void (*free_fn)(void *);

int main(int argc, char **argv) {
    const char *dll = (argc > 1) ? argv[1] : "libjemalloc.dll";

    HMODULE h = LoadLibraryA(dll);
    if (!h) {
        fprintf(stderr, "LoadLibrary(%s) failed: %lu\n", dll, (unsigned long)GetLastError());
        return 2;
    }

    /* jemalloc's Windows/mingw build usually prefixes exports with je_; fall
     * back to the unprefixed names in case it was built without a prefix. */
    malloc_fn jm = (malloc_fn)(void *)GetProcAddress(h, "je_malloc");
    free_fn   jf = (free_fn)(void *)GetProcAddress(h, "je_free");
    if (!jm || !jf) {
        jm = (malloc_fn)(void *)GetProcAddress(h, "malloc");
        jf = (free_fn)(void *)GetProcAddress(h, "free");
    }
    if (!jm || !jf) {
        fprintf(stderr, "could not resolve je_malloc/je_free (or malloc/free) exports\n");
        return 3;
    }

    void *p = jm(1024);
    if (!p) {
        fprintf(stderr, "jemalloc malloc(1024) returned NULL\n");
        return 4;
    }
    memset(p, 0xAB, 1024);
    jf(p);

    printf("jemalloc smoke OK: allocate+free through the DLL works\n");
    return 0;
}
