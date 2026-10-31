/*
 * thread_init_kill.exe [creators] [kills per creator]: threads killed during their startup must not hang.
 *
 * Helldivers 2's anti-tamper code creates suspended threads with no start address and kills them right away.
 * Wine (since 6.2) keeps the write end of a new thread's reply pipe open in the thread until its init_thread
 * request returns, so a thread killed after it sent that request but before the server read it waits for the
 * reply forever, and one killed just before leaks the write end. Each creator here does the game's pattern as
 * fast as it can, then the program compares its own Linux thread and fd counts with the ones it started with. It
 * reads them from /proc/<pid> of its own Unix process, which it finds by name: Wine's server opens files for its
 * clients, so Z:\proc\self would be the server.
 *
 * The same churn makes the server drain fds of threads that are already gone while it handles a new_thread
 * request, and get_thread_from_id() failing for those used to turn the request's status into STATUS_INVALID_CID:
 * NtCreateThreadEx() fails although the thread and its handle exist, and the handle leaks. So the program also
 * counts failed creations. With more load (16 2000), a creation can also fail with STATUS_ACCESS_VIOLATION and
 * leave one fd behind: GE's freeing of killed threads' stacks had put a TEB on its list twice, and its
 * pthread_tryjoin_np() faulted on the second pass.
 *
 * Expected with the fixes: "0 hang", fds +0 and 0 create errors. Stock Wine leaves hundreds of threads and
 * thousands of fds, and some creations fail with STATUS_INVALID_CID (rarely with ntsync).
 * Build: x86_64-w64-mingw32-gcc -O2 -o thread_init_kill.exe thread_init_kill.c (or i686- for 32-bit)
 */
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef NTSTATUS (WINAPI *create_t)(HANDLE *, ACCESS_MASK, void *, HANDLE, void *, void *, ULONG,
                                    SIZE_T, SIZE_T, SIZE_T, void *);
typedef NTSTATUS (WINAPI *terminate_t)(HANDLE, NTSTATUS);

static create_t pNtCreateThreadEx;
static terminate_t pNtTerminateThread;
static int kills_per_creator;
static volatile LONG kills, timeouts, errors, first_error;

static char proc_dir[64]; /* Z:\proc\<pid> of this process */

static BOOL read_small_file(const char *path, char *buf, DWORD size)
{
    DWORD got = 0;
    HANDLE f = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);

    if (f == INVALID_HANDLE_VALUE) return FALSE;
    ReadFile(f, buf, size - 1, &got, NULL);
    CloseHandle(f);
    buf[got] = 0;
    return TRUE;
}

/* The Unix process whose name is this program's, as Linux keeps it (15 characters at most). */
static BOOL find_own_process(void)
{
    char exe[MAX_PATH], name[16], path[MAX_PATH], buf[64], *base;
    WIN32_FIND_DATAA data;
    HANDLE h;
    int found = 0;

    GetModuleFileNameA(NULL, exe, sizeof(exe));
    base = strrchr(exe, '\\') ? strrchr(exe, '\\') + 1 : exe;
    lstrcpynA(name, base, sizeof(name));
    if ((h = FindFirstFileA("Z:\\proc\\*", &data)) == INVALID_HANDLE_VALUE) return FALSE;
    do
    {
        if (data.cFileName[0] < '0' || data.cFileName[0] > '9') continue;
        sprintf(path, "Z:\\proc\\%s\\comm", data.cFileName);
        if (!read_small_file(path, buf, sizeof(buf))) continue;
        buf[strcspn(buf, "\n")] = 0;
        if (strcmp(buf, name)) continue;
        sprintf(proc_dir, "Z:\\proc\\%s", data.cFileName);
        found++;
    } while (FindNextFileA(h, &data));
    FindClose(h);
    return found == 1;
}

static int linux_threads(void)
{
    char path[MAX_PATH], buf[8192], *p;

    sprintf(path, "%s\\status", proc_dir);
    if (!read_small_file(path, buf, sizeof(buf))) return -1;
    return (p = strstr(buf, "\nThreads:")) ? atoi(p + 9) : -1;
}

static int linux_fds(void)
{
    char path[MAX_PATH];
    WIN32_FIND_DATAA data;
    HANDLE h;
    int n = 0;

    sprintf(path, "%s\\fd\\*", proc_dir);
    if ((h = FindFirstFileA(path, &data)) == INVALID_HANDLE_VALUE) return -1;
    do if (data.cFileName[0] != '.') n++; while (FindNextFileA(h, &data));
    FindClose(h);
    return n;
}

static DWORD WINAPI creator(void *arg)
{
    int i;

    for (i = 0; i < kills_per_creator; i++)
    {
        HANDLE h;
        /* suspended (1), every other one also hidden from debuggers (5), no start address, 1 MiB stack */
        NTSTATUS status = pNtCreateThreadEx(&h, THREAD_ALL_ACCESS, NULL, GetCurrentProcess(), NULL, NULL,
                                            (i & 1) ? 5 : 1, 0, 0, 0x100000, NULL);
        if (status)
        {
            InterlockedIncrement(&errors);
            InterlockedCompareExchange(&first_error, (LONG)status, 0);
            continue;
        }
        if (i % 3 == 1) SwitchToThread();
        pNtTerminateThread(h, 0);
        if (WaitForSingleObject(h, 5000) != WAIT_OBJECT_0) InterlockedIncrement(&timeouts);
        CloseHandle(h);
        InterlockedIncrement(&kills);
    }
    return 0;
}

static DWORD WINAPI quick(void *arg) { return 0; }

int main(int argc, char **argv)
{
    int creators = argc > 1 ? atoi(argv[1]) : 8, i, t0, f0, t1, f1, prev;
    HMODULE ntdll = GetModuleHandleA("ntdll.dll");
    HANDLE th[64], h;

    kills_per_creator = argc > 2 ? atoi(argv[2]) : 500;
    if (creators < 1 || creators > 64) creators = 8;
    pNtCreateThreadEx = (create_t)GetProcAddress(ntdll, "NtCreateThreadEx");
    pNtTerminateThread = (terminate_t)GetProcAddress(ntdll, "NtTerminateThread");

    if (!find_own_process())
    {
        printf("thread_init_kill: cannot find this program's Unix process in Z:\\proc (not Wine?)\n");
        return 2;
    }
    Sleep(200);
    t0 = linux_threads();
    f0 = linux_fds();
    for (i = 0; i < creators; i++) th[i] = CreateThread(NULL, 0, creator, NULL, 0, NULL);
    WaitForMultipleObjects(creators, th, TRUE, INFINITE);
    for (i = 0; i < creators; i++) CloseHandle(th[i]);
    /* a few ordinary threads, then wait until the thread count stops falling */
    for (i = 0; i < 4; i++)
    {
        h = CreateThread(NULL, 0, quick, NULL, 0, NULL);
        WaitForSingleObject(h, INFINITE);
        CloseHandle(h);
    }
    t1 = linux_threads();
    for (i = 0; i < 20; i++)
    {
        Sleep(100);
        prev = t1;
        if ((t1 = linux_threads()) >= prev && i >= 4) break;
    }
    f1 = linux_fds();
    printf("thread_init_kill: %ld kills by %d threads, %ld waits timed out, %ld create errors (first %#lx); "
           "Linux threads %d before, %d after: %d hang; fds %d before, %d after: %+d (%s)\n",
           kills, creators, timeouts, errors, (unsigned long)first_error, t0, t1, t1 - t0, f0, f1, f1 - f0,
           proc_dir + 3);
    return t1 - t0 > 0 || f1 - f0 > 0 || errors > 0;
}
