/*
 * jemalloc-run.exe  (issue #28, Windows Detours injection)
 *
 * Usage: jemalloc-run.exe <command> [args...]
 *
 * Launches <command> with jemalloc-shim.dll injected via Detours, so the child
 * process's allocations are served by jemalloc. This is the Windows equivalent
 * of the Unix LD_PRELOAD model: wrap the command whose allocations you want to
 * route through jemalloc. The shim DLL must sit next to this executable.
 */
#include <windows.h>
#include <detours.h>
#include <cstdio>
#include <cstring>
#include <string>

/* Quote one argument for a Windows command line (CommandLineToArgvW rules). */
static std::string quote_arg(const char *arg) {
    std::string out;
    bool needs = !*arg;
    for (const char *p = arg; *p; ++p) {
        if (*p == ' ' || *p == '\t' || *p == '"') { needs = true; break; }
    }
    if (!needs) return std::string(arg);
    out.push_back('"');
    for (const char *p = arg;; ++p) {
        unsigned backslashes = 0;
        while (*p == '\\') { ++backslashes; ++p; }
        if (*p == '\0') {
            out.append(backslashes * 2, '\\');
            break;
        } else if (*p == '"') {
            out.append(backslashes * 2 + 1, '\\');
            out.push_back('"');
        } else {
            out.append(backslashes, '\\');
            out.push_back(*p);
        }
    }
    out.push_back('"');
    return out;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: jemalloc-run <command> [args...]\n");
        return 2;
    }

    /* Locate jemalloc-shim.dll next to this executable. */
    char exe[MAX_PATH];
    DWORD n = GetModuleFileNameA(nullptr, exe, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) {
        fprintf(stderr, "jemalloc-run: cannot resolve own path\n");
        return 2;
    }
    char *slash = strrchr(exe, '\\');
    if (!slash) {
        fprintf(stderr, "jemalloc-run: bad own path\n");
        return 2;
    }
    std::string shim(exe, slash - exe + 1);
    shim += "jemalloc-shim.dll";

    /* Build the child command line from argv[1..]. */
    std::string cmd;
    for (int i = 1; i < argc; ++i) {
        if (i > 1) cmd.push_back(' ');
        cmd += quote_arg(argv[i]);
    }

    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    const char *dlls[1] = {shim.c_str()};

    /* Mutable buffer for the command line (CreateProcess may modify it). */
    std::string cmdbuf = cmd;

    BOOL ok = DetourCreateProcessWithDllsA(
        nullptr, &cmdbuf[0], nullptr, nullptr, TRUE,
        CREATE_DEFAULT_ERROR_MODE, nullptr, nullptr,
        &si, &pi, 1, dlls, nullptr);

    if (!ok) {
        fprintf(stderr, "jemalloc-run: DetourCreateProcessWithDlls failed: %lu\n",
                (unsigned long)GetLastError());
        return 2;
    }

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}
