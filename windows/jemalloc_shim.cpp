/*
 * jemalloc-shim.dll  (issue #28, Windows Detours injection)
 *
 * Injected into a target process by jemalloc-run.exe (via Detours) before the
 * target's entry point. On attach it loads jemalloc.dll (sitting next to this
 * shim) and detours the UCRT allocator (malloc/free/calloc/realloc/_msize) so
 * the process's allocations are served by jemalloc.
 *
 * Robustness: every jemalloc-served block carries a 16-byte magic header, so
 * free()/realloc()/_msize() can recognise jemalloc-owned pointers and pass any
 * FOREIGN pointer (e.g. allocated by the CRT before hooks were installed) back
 * to the original CRT function instead of handing it to jemalloc — which would
 * otherwise corrupt/crash on a mixed-allocator free.
 *
 * On detach it writes the number of allocations it served to the file named by
 * the JEMALLOC_SHIM_STATS environment variable (used by CI to prove real use).
 */
#include <windows.h>
#include <detours.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <malloc.h> /* _msize */

/* Marker export so the injected payload is unambiguously a real module. */
extern "C" __declspec(dllexport) void jemalloc_shim_present(void) {}

/* ---- jemalloc entry points (resolved from jemalloc.dll) ------------------ */
typedef void  *(*je_malloc_t)(size_t);
typedef void   (*je_free_t)(void *);
typedef void  *(*je_realloc_t)(void *, size_t);

static je_malloc_t  je_malloc  = nullptr;
static je_free_t    je_free    = nullptr;
static je_realloc_t je_realloc = nullptr;

/* ---- original CRT entry points (Detour trampolines) ---------------------- */
static void  *(*real_malloc)(size_t)          = malloc;
static void   (*real_free)(void *)            = free;
static void  *(*real_calloc)(size_t, size_t)  = calloc;
static void  *(*real_realloc)(void *, size_t) = realloc;
static size_t (*real_msize)(void *)           = _msize;

/* ---- magic header -------------------------------------------------------- */
#define JE_MAGIC 0x6A656D31u /* 'jem1' */

typedef struct Header {
    uint32_t magic;
    uint32_t pad;
    size_t   size; /* user-visible size */
} Header;

static const size_t HDR = 16; /* == sizeof(Header) on x64; keeps user ptr 16-aligned */

static volatile LONG g_served = 0;

static inline void *user_from_base(void *base) { return (char *)base + HDR; }
static inline Header *hdr_from_user(void *user) { return (Header *)((char *)user - HDR); }

static void *je_alloc(size_t n) {
    if (n > (SIZE_MAX - HDR)) return nullptr;
    void *base = je_malloc(n + HDR);
    if (!base) return nullptr;
    Header *h = (Header *)base;
    h->magic = JE_MAGIC;
    h->pad = 0;
    h->size = n;
    InterlockedIncrement(&g_served);
    return user_from_base(base);
}

static int is_ours(void *user) {
    if (!user) return 0;
    return hdr_from_user(user)->magic == JE_MAGIC;
}

/* ---- hooks --------------------------------------------------------------- */
static void *hook_malloc(size_t n) {
    return je_alloc(n);
}

static void hook_free(void *p) {
    if (!p) return;
    if (is_ours(p)) {
        je_free(hdr_from_user(p));
    } else {
        real_free(p); /* foreign pointer: hand back to the CRT */
    }
}

static void *hook_calloc(size_t count, size_t size) {
    size_t total;
    if (count && size > (SIZE_MAX / count)) return nullptr; /* overflow */
    total = count * size;
    void *p = je_alloc(total);
    if (p) memset(p, 0, total);
    return p;
}

static void *hook_realloc(void *p, size_t n) {
    if (!p) return je_alloc(n);
    if (!is_ours(p)) return real_realloc(p, n); /* foreign: stay with the CRT */
    if (n == 0) { je_free(hdr_from_user(p)); return nullptr; }
    if (n > (SIZE_MAX - HDR)) return nullptr;
    void *base = je_realloc(hdr_from_user(p), n + HDR);
    if (!base) return nullptr;
    Header *h = (Header *)base;
    h->size = n;
    return user_from_base(base);
}

static size_t hook_msize(void *p) {
    if (!p) return 0;
    if (is_ours(p)) return hdr_from_user(p)->size;
    return real_msize(p);
}

/* ---- setup --------------------------------------------------------------- */
static int load_jemalloc() {
    char path[MAX_PATH];
    HMODULE self = nullptr;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCSTR)&load_jemalloc, &self);
    DWORD n = GetModuleFileNameA(self, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 0;
    /* replace the shim's file name with jemalloc.dll */
    char *slash = strrchr(path, '\\');
    if (!slash) return 0;
    strcpy(slash + 1, "jemalloc.dll");

    /* LOAD_WITH_ALTERED_SEARCH_PATH so jemalloc.dll's own deps resolve from
     * its directory (mingw runtime DLLs are shipped alongside it). */
    HMODULE jm = LoadLibraryExA(path, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!jm) return 0;

    je_malloc  = (je_malloc_t)(void *)GetProcAddress(jm, "je_malloc");
    je_free    = (je_free_t)(void *)GetProcAddress(jm, "je_free");
    je_realloc = (je_realloc_t)(void *)GetProcAddress(jm, "je_realloc");
    return je_malloc && je_free && je_realloc;
}

static void write_stats() {
    char *f = getenv("JEMALLOC_SHIM_STATS");
    if (!f || !*f) return;
    FILE *fp = fopen(f, "w");
    if (!fp) return;
    fprintf(fp, "%ld\n", (long)g_served);
    fclose(fp);
}

static void attach_all() {
    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    DetourAttach(&(PVOID &)real_malloc, (PVOID)hook_malloc);
    DetourAttach(&(PVOID &)real_free, (PVOID)hook_free);
    DetourAttach(&(PVOID &)real_calloc, (PVOID)hook_calloc);
    DetourAttach(&(PVOID &)real_realloc, (PVOID)hook_realloc);
    DetourAttach(&(PVOID &)real_msize, (PVOID)hook_msize);
    DetourTransactionCommit();
}

static void detach_all() {
    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    DetourDetach(&(PVOID &)real_malloc, (PVOID)hook_malloc);
    DetourDetach(&(PVOID &)real_free, (PVOID)hook_free);
    DetourDetach(&(PVOID &)real_calloc, (PVOID)hook_calloc);
    DetourDetach(&(PVOID &)real_realloc, (PVOID)hook_realloc);
    DetourDetach(&(PVOID &)real_msize, (PVOID)hook_msize);
    DetourTransactionCommit();
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD reason, LPVOID reserved) {
    (void)hinst;
    (void)reserved;
    if (DetourIsHelperProcess()) return TRUE;

    if (reason == DLL_PROCESS_ATTACH) {
        DetourRestoreAfterWith();
        if (!load_jemalloc()) {
            /* Could not load jemalloc — leave the CRT allocator untouched so
             * the target still runs (verified count will be 0, failing CI). */
            return TRUE;
        }
        attach_all();
    } else if (reason == DLL_PROCESS_DETACH) {
        write_stats();
        if (je_malloc) detach_all();
    }
    return TRUE;
}
