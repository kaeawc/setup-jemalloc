/*
 * jemalloc_interpose.dylib  (issue #32, macOS)
 *
 * On modern macOS, DYLD_INSERT_LIBRARIES of jemalloc alone does NOT replace the
 * allocator (the zone override and flat-namespace interposition both fail to
 * route malloc() to jemalloc). The supported mechanism is dyld interposition
 * (__DATA,__interpose): this dylib redirects the CRT allocator to jemalloc's
 * je_* functions and is loaded via DYLD_INSERT_LIBRARIES ahead of the process.
 *
 * A 16-byte magic header lets free()/realloc()/malloc_size() recognise
 * jemalloc-owned pointers and pass FOREIGN pointers (allocated by libSystem
 * before/around interposition) back to the original allocator instead of
 * handing them to jemalloc — avoiding mixed-allocator crashes.
 */
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dlfcn.h>
#include <malloc/malloc.h>

/* jemalloc (je_-prefixed), resolved from the linked libjemalloc dylib. */
extern void  *je_malloc(size_t);
extern void   je_free(void *);
extern void  *je_realloc(void *, size_t);

/* Original system allocator, for foreign pointers. */
static void  *(*sys_malloc)(size_t);
static void   (*sys_free)(void *);
static void  *(*sys_realloc)(void *, size_t);
static size_t (*sys_malloc_size)(const void *);

#include <stdio.h>
static volatile long g_calls = 0;

__attribute__((destructor))
static void write_stats(void) {
    const char *f = getenv("JEMALLOC_INTERPOSE_STATS");
    if (!f || !*f) return;
    FILE *fp = fopen(f, "w");
    if (!fp) return;
    fprintf(fp, "%ld\n", g_calls);
    fclose(fp);
}

__attribute__((constructor))
static void init_sys(void) {
    sys_malloc      = (void *(*)(size_t))dlsym(RTLD_NEXT, "malloc");
    sys_free        = (void (*)(void *))dlsym(RTLD_NEXT, "free");
    sys_realloc     = (void *(*)(void *, size_t))dlsym(RTLD_NEXT, "realloc");
    sys_malloc_size = (size_t (*)(const void *))dlsym(RTLD_NEXT, "malloc_size");
}

#define JE_MAGIC 0x6A656D31u /* 'jem1' */
enum { HDR = 16 };
typedef struct { uint32_t magic; uint32_t pad; size_t size; } Header;

static void *je_alloc(size_t n) {
    if (n > SIZE_MAX - HDR) return NULL;
    void *base = je_malloc(n + HDR);
    if (!base) return NULL;
    Header *h = (Header *)base;
    h->magic = JE_MAGIC;
    h->pad = 0;
    h->size = n;
    return (char *)base + HDR;
}

static int owned(const void *u) {
    if (!u) return 0;
    return ((const Header *)((const char *)u - HDR))->magic == JE_MAGIC;
}

static void *my_malloc(size_t n) { __sync_fetch_and_add(&g_calls, 1); return je_alloc(n); }

static void my_free(void *p) {
    if (!p) return;
    if (owned(p)) je_free((char *)p - HDR);
    else if (sys_free) sys_free(p);
}

static void *my_calloc(size_t count, size_t size) {
    size_t total;
    if (count && size > SIZE_MAX / count) return NULL;
    total = count * size;
    void *p = je_alloc(total);
    if (p) memset(p, 0, total);
    return p;
}

static void *my_realloc(void *p, size_t n) {
    if (!p) return je_alloc(n);
    if (!owned(p)) return sys_realloc ? sys_realloc(p, n) : NULL;
    if (n == 0) { je_free((char *)p - HDR); return NULL; }
    if (n > SIZE_MAX - HDR) return NULL;
    void *base = je_realloc((char *)p - HDR, n + HDR);
    if (!base) return NULL;
    ((Header *)base)->size = n;
    return (char *)base + HDR;
}

static size_t my_malloc_size(const void *p) {
    if (p && owned(p)) return ((const Header *)((const char *)p - HDR))->size;
    return sys_malloc_size ? sys_malloc_size(p) : 0;
}

#define DYLD_INTERPOSE(_replacement, _replacee)                                \
    __attribute__((used)) static struct {                                      \
        const void *replacement;                                               \
        const void *replacee;                                                  \
    } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&_replacement,                            \
        (const void *)(unsigned long)&_replacee                                \
    }

DYLD_INTERPOSE(my_malloc, malloc);
DYLD_INTERPOSE(my_free, free);
DYLD_INTERPOSE(my_calloc, calloc);
DYLD_INTERPOSE(my_realloc, realloc);
DYLD_INTERPOSE(my_malloc_size, malloc_size);
