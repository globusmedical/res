/* Long path support for the Win32-hosted toolchain programs.

   msvcrt's narrow file functions go through the ANSI Win32 API, which rejects
   paths of MAX_PATH (260) characters or more. Cygwin, which hosted the
   original toolchain, has no such limit, and gcc routinely builds long paths:
   the driver locates headers and libraries as <prefix>/bin/../lib/gcc/<target>
   /4.1.0/../../../../include/..., which exceeds the limit once the package
   sits in a deep directory such as a grab store.

   Linked into every host program, this object replaces the msvcrt entries of
   the program's import address table for the path-taking functions. Paths
   shorter than LONG_PATH are passed through unchanged. Longer ones are made
   absolute and their "." and ".." components collapsed, as Win32 itself does
   lexically; if that is still too long, the wide-character function is called
   with a \\?\ path, which has no length limit. */

#include <windows.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <wchar.h>
#include <wctype.h>

/* CreateDirectory is limited to MAX_PATH - 12 characters, the rest to MAX_PATH. */
#define LONG_PATH 248

/* Lets the build check that every host program carries this object. */
const char gmas_longpath_marker[] __attribute__((used)) = "gmas-longpath-1";

typedef int (__cdecl *fn_open)(const char *, int, ...);
typedef void *(__cdecl *fn_fopen)(const char *, const char *);
typedef void *(__cdecl *fn_freopen)(const char *, const char *, void *);
typedef int (__cdecl *fn_path)(const char *);
typedef int (__cdecl *fn_path_int)(const char *, int);
typedef int (__cdecl *fn_path_ptr)(const char *, void *);
typedef int (__cdecl *fn_rename)(const char *, const char *);
typedef intptr_t (__cdecl *fn_spawnv)(int, const char *, const char *const *);

typedef int (__cdecl *fn_wopen)(const wchar_t *, int, ...);
typedef void *(__cdecl *fn_wfopen)(const wchar_t *, const wchar_t *);
typedef void *(__cdecl *fn_wfreopen)(const wchar_t *, const wchar_t *, void *);
typedef int (__cdecl *fn_wpath)(const wchar_t *);
typedef int (__cdecl *fn_wpath_int)(const wchar_t *, int);
typedef int (__cdecl *fn_wpath_ptr)(const wchar_t *, void *);
typedef int (__cdecl *fn_wrename)(const wchar_t *, const wchar_t *);

static fn_open o_open;
static fn_fopen o_fopen;
static fn_freopen o_freopen;
static fn_path_ptr o_stat, o_stat64, o_utime;
static fn_path_int o_access, o_chmod;
static fn_path o_unlink, o_remove, o_mkdir, o_rmdir;
static fn_rename o_rename;
static fn_spawnv o_spawnv, o_spawnvp;

static fn_wopen w_open;
static fn_wfopen w_fopen;
static fn_wfreopen w_freopen;
static fn_wpath_ptr w_utime;
static fn_wpath_int w_access, w_chmod;
static fn_wpath w_unlink, w_remove, w_mkdir, w_rmdir;
static fn_wrename w_rename;

static int is_sep(char c) { return c == '/' || c == '\\'; }

/* Returns a malloc'ed absolute path with "." and ".." collapsed and
   backslash separators, or NULL if the path cannot be normalized. */
static char *normalize(const char *path)
{
    char *full, *out, *seg, *next;
    size_t root, len, cwdlen;

    if (path[0] && path[1] == ':' && is_sep(path[2])) {
        full = strdup(path);
    } else if (is_sep(path[0]) && is_sep(path[1])) {
        return NULL; /* UNC and device paths are left alone. */
    } else {
        cwdlen = GetCurrentDirectoryA(0, NULL);
        if (cwdlen == 0)
            return NULL;
        full = malloc(cwdlen + strlen(path) + 2);
        if (!full)
            return NULL;
        GetCurrentDirectoryA((DWORD)cwdlen, full);
        if (full[0] == '\\' || full[1] != ':') {
            free(full);
            return NULL;
        }
        if (is_sep(path[0]))
            strcpy(full + 2, path); /* root of the current drive */
        else if (path[0] && path[1] == ':')
            return free(full), NULL; /* drive-relative, e.g. "C:foo" */
        else {
            len = strlen(full);
            if (!is_sep(full[len - 1]))
                full[len++] = '\\';
            strcpy(full + len, path);
        }
    }
    if (!full)
        return NULL;

    out = malloc(strlen(full) + 1);
    if (!out)
        return free(full), NULL;
    out[0] = full[0];
    out[1] = ':';
    out[2] = '\\';
    root = len = 3;
    for (seg = full + 3; *seg; seg = next) {
        size_t n = 0;
        while (seg[n] && !is_sep(seg[n]))
            n++;
        next = seg + n;
        while (is_sep(*next))
            next++;
        if (n == 0 || (n == 1 && seg[0] == '.'))
            continue;
        if (n == 2 && seg[0] == '.' && seg[1] == '.') {
            if (len > root) {
                len--; /* drop the trailing separator */
                while (len > root && out[len - 1] != '\\')
                    len--;
            }
            continue;
        }
        memcpy(out + len, seg, n);
        len += n;
        if (*next)
            out[len++] = '\\';
    }
    /* Keep a trailing separator only where the input had one. */
    if (len > root && out[len - 1] == '\\' && !is_sep(full[strlen(full) - 1]))
        len--;
    out[len] = 0;
    free(full);
    return out;
}

static wchar_t *to_wide(const char *s, int prefix)
{
    int n = MultiByteToWideChar(CP_ACP, 0, s, -1, NULL, 0);
    wchar_t *w;
    if (n <= 0)
        return NULL;
    w = malloc((n + 4) * sizeof(wchar_t));
    if (!w)
        return NULL;
    if (prefix)
        wcscpy(w, L"\\\\?\\");
    MultiByteToWideChar(CP_ACP, 0, s, -1, w + (prefix ? 4 : 0), n);
    return w;
}

/* A long path is resolved into either a shorter narrow path (*narrow) or a
   \\?\ wide path (*wide). Returns 0 if the path should be used as is. */
static int resolve(const char *path, char **narrow, wchar_t **wide)
{
    char *n;
    *narrow = NULL;
    *wide = NULL;
    if (!path || strlen(path) < LONG_PATH)
        return 0;
    n = normalize(path);
    if (!n)
        return 0;
    if (strlen(n) < LONG_PATH) {
        *narrow = n;
        return 1;
    }
    *wide = to_wide(n, 1);
    free(n);
    return *wide != NULL;
}

#define WITH_PATH(path, call_orig, call_wide)                             \
    char *n_;                                                                   \
    wchar_t *w_;                                                                \
    if (!resolve(path, &n_, &w_))                                               \
        return call_orig(path);                                                 \
    if (n_) {                                                                   \
        __typeof__(call_orig(path)) r_ = call_orig(n_);                         \
        int e_ = errno;                                                         \
        free(n_);                                                               \
        errno = e_;                                                             \
        return r_;                                                              \
    } else {                                                                    \
        __typeof__(call_orig(path)) r_ = call_wide(w_);                         \
        int e_ = errno;                                                         \
        free(w_);                                                               \
        errno = e_;                                                             \
        return r_;                                                              \
    }

static int __cdecl h_open(const char *path, int flags, ...)
{
    int mode = 0;
    if (flags & _O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, int);
        va_end(ap);
    }
#define O(p) o_open(p, flags, mode)
#define W(p) w_open(p, flags, mode)
    WITH_PATH(path, O, W)
#undef O
#undef W
}

static void *__cdecl h_fopen(const char *path, const char *mode)
{
    wchar_t wmode[16];
    MultiByteToWideChar(CP_ACP, 0, mode, -1, wmode, 16);
    wmode[15] = 0;
#define O(p) o_fopen(p, mode)
#define W(p) w_fopen(p, wmode)
    WITH_PATH(path, O, W)
#undef O
#undef W
}

static void *__cdecl h_freopen(const char *path, const char *mode, void *f)
{
    wchar_t wmode[16];
    MultiByteToWideChar(CP_ACP, 0, mode, -1, wmode, 16);
    wmode[15] = 0;
#define O(p) o_freopen(p, mode, f)
#define W(p) w_freopen(p, wmode, f)
    WITH_PATH(path, O, W)
#undef O
#undef W
}

/* msvcrt's _wstat rejects \\?\ paths, so long paths are stat'ed here with the
   same st_mode, st_dev and st_nlink conventions as msvcrt. */
static int wide_stat(const wchar_t *path, __int64 *size, __int64 t[3], unsigned short *mode, int *drive)
{
    WIN32_FILE_ATTRIBUTE_DATA a;
    const wchar_t *ext;
    FILETIME *ft[3];
    int i;

    if (!GetFileAttributesExW(path, GetFileExInfoStandard, &a)) {
        DWORD e = GetLastError();
        errno = (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND || e == ERROR_INVALID_NAME)
                    ? ENOENT : EACCES;
        return -1;
    }
    *mode = (a.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? (_S_IFDIR | _S_IEXEC) : _S_IFREG;
    *mode |= _S_IREAD;
    if (!(a.dwFileAttributes & FILE_ATTRIBUTE_READONLY))
        *mode |= _S_IWRITE;
    ext = wcsrchr(path, L'.');
    if (ext && (!_wcsicmp(ext, L".exe") || !_wcsicmp(ext, L".com") || !_wcsicmp(ext, L".bat")
                || !_wcsicmp(ext, L".cmd")))
        *mode |= _S_IEXEC;
    *mode |= (*mode & 0700) >> 3;
    *mode |= (*mode & 0700) >> 6;
    *size = ((__int64)a.nFileSizeHigh << 32) | a.nFileSizeLow;
    ft[0] = &a.ftLastAccessTime;
    ft[1] = &a.ftLastWriteTime;
    ft[2] = &a.ftCreationTime;
    for (i = 0; i < 3; i++) {
        __int64 v = ((__int64)ft[i]->dwHighDateTime << 32) | ft[i]->dwLowDateTime;
        t[i] = v ? v / 10000000 - 11644473600LL : 0;
    }
    /* path is \\?\X:\... */
    *drive = towupper(path[4]) - L'A';
    return 0;
}

static int __cdecl wide_stat32(const wchar_t *path, void *buf)
{
    struct _stat32 *st = buf;
    __int64 size, t[3];
    unsigned short mode;
    int drive;
    if (wide_stat(path, &size, t, &mode, &drive))
        return -1;
    memset(st, 0, sizeof *st);
    st->st_dev = st->st_rdev = drive;
    st->st_mode = mode;
    st->st_nlink = 1;
    st->st_size = (_off_t)size;
    st->st_atime = (__time32_t)t[0];
    st->st_mtime = (__time32_t)t[1];
    st->st_ctime = (__time32_t)t[2];
    return 0;
}

static int __cdecl wide_stat64(const wchar_t *path, void *buf)
{
    struct _stat64 *st = buf;
    __int64 size, t[3];
    unsigned short mode;
    int drive;
    if (wide_stat(path, &size, t, &mode, &drive))
        return -1;
    memset(st, 0, sizeof *st);
    st->st_dev = st->st_rdev = drive;
    st->st_mode = mode;
    st->st_nlink = 1;
    st->st_size = size;
    st->st_atime = t[0];
    st->st_mtime = t[1];
    st->st_ctime = t[2];
    return 0;
}

#define O_stat(p) o_stat(p, buf)
#define W_stat(p) wide_stat32(p, buf)
#define O_stat64(p) o_stat64(p, buf)
#define W_stat64(p) wide_stat64(p, buf)
#define O_utime(p) o_utime(p, buf)
#define W_utime(p) w_utime(p, buf)
static int __cdecl h_stat(const char *path, void *buf) { WITH_PATH(path, O_stat, W_stat) }
static int __cdecl h_stat64(const char *path, void *buf) { WITH_PATH(path, O_stat64, W_stat64) }
static int __cdecl h_utime(const char *path, void *buf) { WITH_PATH(path, O_utime, W_utime) }

#define O_access(p) o_access(p, mode)
#define W_access(p) w_access(p, mode)
#define O_chmod(p) o_chmod(p, mode)
#define W_chmod(p) w_chmod(p, mode)
static int __cdecl h_access(const char *path, int mode) { WITH_PATH(path, O_access, W_access) }
static int __cdecl h_chmod(const char *path, int mode) { WITH_PATH(path, O_chmod, W_chmod) }

static int __cdecl h_unlink(const char *path) { WITH_PATH(path, o_unlink, w_unlink) }
static int __cdecl h_remove(const char *path) { WITH_PATH(path, o_remove, w_remove) }
static int __cdecl h_mkdir(const char *path) { WITH_PATH(path, o_mkdir, w_mkdir) }
static int __cdecl h_rmdir(const char *path) { WITH_PATH(path, o_rmdir, w_rmdir) }

static int __cdecl h_rename(const char *from, const char *to)
{
    char *nf, *nt;
    wchar_t *wf, *wt;
    int r, e, lf = resolve(from, &nf, &wf), lt = resolve(to, &nt, &wt);
    if (!lf && !lt)
        return o_rename(from, to);
    if (!wf && !wt) {
        r = o_rename(nf ? nf : from, nt ? nt : to);
    } else {
        /* Mixed lengths: give both sides to the wide function. */
        if (!wf)
            wf = to_wide(nf ? nf : from, 0);
        if (!wt)
            wt = to_wide(nt ? nt : to, 0);
        r = (wf && wt) ? w_rename(wf, wt) : o_rename(from, to);
    }
    e = errno;
    free(nf), free(nt), free(wf), free(wt);
    errno = e;
    return r;
}

/* CreateProcess has no \\?\ form for the program name, so a long program
   path is only shortened by collapsing "..". */
static intptr_t __cdecl h_spawnv(int mode, const char *path, const char *const *argv)
{
    char *n = strlen(path) >= LONG_PATH ? normalize(path) : NULL;
    intptr_t r = o_spawnv(mode, n ? n : path, argv);
    int e = errno;
    free(n);
    errno = e;
    return r;
}

static intptr_t __cdecl h_spawnvp(int mode, const char *path, const char *const *argv)
{
    char *n = strlen(path) >= LONG_PATH ? normalize(path) : NULL;
    intptr_t r = o_spawnvp(mode, n ? n : path, argv);
    int e = errno;
    free(n);
    errno = e;
    return r;
}

struct hook {
    const char *name;
    void *hook;
    void **orig;
};

static const struct hook hooks[] = {
    {"_open", (void *)h_open, (void **)&o_open},
    {"fopen", (void *)h_fopen, (void **)&o_fopen},
    {"freopen", (void *)h_freopen, (void **)&o_freopen},
    {"_stat", (void *)h_stat, (void **)&o_stat},
    {"_stat64", (void *)h_stat64, (void **)&o_stat64},
    {"_utime", (void *)h_utime, (void **)&o_utime},
    {"_access", (void *)h_access, (void **)&o_access},
    {"_chmod", (void *)h_chmod, (void **)&o_chmod},
    {"_unlink", (void *)h_unlink, (void **)&o_unlink},
    {"remove", (void *)h_remove, (void **)&o_remove},
    {"_mkdir", (void *)h_mkdir, (void **)&o_mkdir},
    {"_rmdir", (void *)h_rmdir, (void **)&o_rmdir},
    {"rename", (void *)h_rename, (void **)&o_rename},
    {"_spawnv", (void *)h_spawnv, (void **)&o_spawnv},
    {"_spawnvp", (void *)h_spawnvp, (void **)&o_spawnvp},
};

__attribute__((constructor)) static void install_hooks(void)
{
    HMODULE crt = GetModuleHandleA("msvcrt.dll");
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    PIMAGE_NT_HEADERS nt = (PIMAGE_NT_HEADERS)(base + ((PIMAGE_DOS_HEADER)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    PIMAGE_IMPORT_DESCRIPTOR d;
    size_t i;

    if (!crt || !dir.VirtualAddress)
        return;
#define WIDE(var, name) var = (__typeof__(var))GetProcAddress(crt, name)
    WIDE(w_open, "_wopen");
    WIDE(w_fopen, "_wfopen");
    WIDE(w_freopen, "_wfreopen");
    WIDE(w_utime, "_wutime");
    WIDE(w_access, "_waccess");
    WIDE(w_chmod, "_wchmod");
    WIDE(w_unlink, "_wunlink");
    WIDE(w_remove, "_wremove");
    WIDE(w_mkdir, "_wmkdir");
    WIDE(w_rmdir, "_wrmdir");
    WIDE(w_rename, "_wrename");
#undef WIDE

    for (d = (PIMAGE_IMPORT_DESCRIPTOR)(base + dir.VirtualAddress); d->Name; d++) {
        PIMAGE_THUNK_DATA names, iat;
        if (_stricmp((const char *)base + d->Name, "msvcrt.dll") != 0)
            continue;
        names = (PIMAGE_THUNK_DATA)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
        iat = (PIMAGE_THUNK_DATA)(base + d->FirstThunk);
        for (; names->u1.AddressOfData; names++, iat++) {
            const char *name;
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal))
                continue;
            name = (const char *)((PIMAGE_IMPORT_BY_NAME)(base + names->u1.AddressOfData))->Name;
            for (i = 0; i < sizeof hooks / sizeof hooks[0]; i++) {
                DWORD old;
                if (strcmp(name, hooks[i].name) != 0)
                    continue;
                *hooks[i].orig = (void *)iat->u1.Function;
                VirtualProtect(&iat->u1.Function, sizeof iat->u1.Function, PAGE_READWRITE, &old);
                iat->u1.Function = (ULONG_PTR)hooks[i].hook;
                VirtualProtect(&iat->u1.Function, sizeof iat->u1.Function, old, &old);
                break;
            }
        }
    }
}
