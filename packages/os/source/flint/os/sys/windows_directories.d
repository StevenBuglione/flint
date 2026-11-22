/// Windows directory traversal for root-relative globbing.
///
/// Each open directory is pinned by a handle and identified by its volume serial number and file index. An entry
/// below the root is opened by path and accepted only when its final path, after the kernel resolved every link,
/// still lies beneath the root's final path; the handle then pins what was checked. Without `follow` a reparse
/// point (symbolic link or junction) is refused, as openat2's RESOLVE_NO_SYMLINKS refuses one on Linux.
module flint.os.sys.windows_directories;

@safe:

version (Windows)
{
    import core.sys.windows.winbase : BY_HANDLE_FILE_INFORMATION, CloseHandle, CreateFileW,
        FILE_FLAG_BACKUP_SEMANTICS, FindClose,
        FindNextFileW, GetFileInformationByHandle, GetLastError, INVALID_HANDLE_VALUE,
        OPEN_EXISTING, WIN32_FIND_DATAW;
    import core.sys.windows.windef : BOOL, DWORD, HANDLE;
    import core.sys.windows.winerror : ERROR_FILE_NOT_FOUND, ERROR_NO_MORE_FILES;
    import core.sys.windows.winnt : FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT,
        FILE_SHARE_DELETE, FILE_SHARE_READ, FILE_SHARE_WRITE;
    import flint.arena : Error, Result, Status;
    import flint.os.sys.windows_process : nativeStatus;

    private enum DWORD openReparsePoint = 0x0020_0000; // FILE_FLAG_OPEN_REPARSE_POINT
    private enum DWORD readAttributes = 0x0080; // FILE_READ_ATTRIBUTES
    private enum DWORD symlinkTag = 0xA000_000C; // IO_REPARSE_TAG_SYMLINK
    private enum DWORD junctionTag = 0xA000_0003; // IO_REPARSE_TAG_MOUNT_POINT
    private enum int findExInfoBasic = 1;
    private enum int findExSearchNameMatch = 0;
    private enum DWORD findFirstExLargeFetch = 2;

    private extern (Windows) @system nothrow @nogc
    {
        DWORD GetFinalPathNameByHandleW(HANDLE file, wchar* path, DWORD length, DWORD flags);
        HANDLE FindFirstFileExW(const(wchar)* name, int level, void* data, int search, void* filter, DWORD flags);
    }

package(flint.os):

    struct FileIdentity
    {
        ulong device;
        ulong inode;
    }

    struct Directory
    {
        private HANDLE handle;
        private HANDLE cursor;
        private wchar[] path; // Final path without a trailing separator and without a terminator.
        FileIdentity identity;
    }

    enum EntryKind : ubyte
    {
        file,
        directory,
        symlink,
        unknown
    }

    struct Entry
    {
        string name;
        EntryKind kind;
    }

    private struct Opened
    {
        HANDLE handle;
        BY_HANDLE_FILE_INFORMATION information;
        wchar[] path;
    }

    // UTF-16 path with a terminator from a UTF-8 path that may end in NUL, or null when it is invalid.
    private wchar[] widen(scope const(char)[] text) nothrow
    {
        import std.utf : toUTF16;

        if (text.length != 0 && text[$ - 1] == '\0')
            text = text[0 .. $ - 1];
        try
            return (toUTF16(text) ~ '\0').dup;
        catch (Exception)
            return null;
    }

    // Open `path` (terminated UTF-16) and read its identity and final path. Closes the handle on every failure.
    // SAFETY: The path is a terminated GC buffer that outlives CreateFileW; the information and final-path calls
    // write only into local storage of the sizes they are given.
    private Result!Opened open(wchar[] path, bool follow, bool directory) @trusted nothrow
    {
        const flags = FILE_FLAG_BACKUP_SEMANTICS | (follow ? 0 : openReparsePoint);
        auto handle = CreateFileW(path.ptr, readAttributes,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, null, OPEN_EXISTING, flags, null);
        if (handle == INVALID_HANDLE_VALUE)
            return Result!Opened(Opened.init, Error(nativeStatus(GetLastError()), "could not open directory"));
        Opened opened;
        opened.handle = handle;
        if (!GetFileInformationByHandle(handle, &opened.information))
        {
            const status = nativeStatus(GetLastError());
            CloseHandle(handle);
            return Result!Opened(Opened.init, Error(status, "could not identify directory"));
        }
        const attributes = opened.information.dwFileAttributes;
        if ((!follow && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) || (directory
                && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0))
        {
            CloseHandle(handle);
            return Result!Opened(Opened.init, Error(Status.notFound, "entry no longer resolves inside glob root"));
        }
        wchar[1024] buffer = void;
        auto length = GetFinalPathNameByHandleW(handle, buffer.ptr, cast(DWORD) buffer.length, 0);
        if (length >= buffer.length)
        {
            auto larger = new wchar[length + 1];
            length = GetFinalPathNameByHandleW(handle, larger.ptr, cast(DWORD) larger.length, 0);
            opened.path = length != 0 && length < larger.length ? larger[0 .. length] : null;
        }
        else
            opened.path = length != 0 ? buffer[0 .. length].dup : null;
        if (opened.path is null)
        {
            const status = nativeStatus(GetLastError());
            CloseHandle(handle);
            return Result!Opened(Opened.init, Error(status, "could not resolve directory path"));
        }
        while (opened.path.length > 1 && opened.path[$ - 1] == '\\')
            opened.path = opened.path[0 .. $ - 1];
        return Result!Opened(opened);
    }

    private Directory adopt(Opened opened) pure nothrow
    {
        const information = opened.information;
        return Directory(opened.handle, null, opened.path, FileIdentity(information.dwVolumeSerialNumber,
                (cast(ulong) information.nFileIndexHigh << 32) | information.nFileIndexLow));
    }

    // Whether `path` is `root` followed by a separator and at least one more unit, ignoring ASCII case.
    private bool beneath(scope const(wchar)[] root, scope const(wchar)[] path) pure nothrow @nogc
    {
        if (path.length <= root.length + 1 || path[root.length] != '\\')
            return false;
        foreach (index, unit; root)
        {
            const other = path[index];
            const a = unit >= 'a' && unit <= 'z' ? cast(wchar)(unit - 32) : unit;
            const b = other >= 'a' && other <= 'z' ? cast(wchar)(other - 32) : other;
            if (a != b)
                return false;
        }
        return true;
    }

    // SAFETY: Closes only the handle this call opened when its final path escapes the root.
    @trusted nothrow private Result!Opened openBeneath(ref const Directory root, string path,
            bool follow, bool directory)
    {
        auto relative = widen(path);
        if (relative is null)
            return Result!Opened(Opened.init, Error(Status.invalidArgument, "invalid glob entry path"));
        foreach (ref unit; relative)
            if (unit == '/')
                unit = '\\';
        auto opened = open(root.path ~ '\\' ~ relative, follow, directory);
        if (!opened.ok)
        {
            const code = opened.error.code;
            return Result!Opened(Opened.init, code == Status.notFound || code == Status.permissionDenied
                    ? Error(Status.notFound, "entry no longer resolves inside glob root") : opened.error);
        }
        if (!beneath(root.path, opened.value.path))
        {
            CloseHandle(opened.value.handle);
            return Result!Opened(Opened.init, Error(Status.notFound, "entry no longer resolves inside glob root"));
        }
        return opened;
    }

    Result!Directory openRoot(string terminatedPath) nothrow
    {
        auto path = widen(terminatedPath);
        if (path is null)
            return Result!Directory(Directory.init, Error(Status.invalidArgument, "could not open glob root"));
        auto opened = open(path, true, true);
        if (!opened.ok)
            return Result!Directory(Directory.init, Error(opened.error.code, "could not open glob root"));
        return Result!Directory(adopt(opened.value));
    }

    Result!Directory descend(ref const Directory root, string path, bool follow) nothrow
    {
        auto opened = openBeneath(root, path, follow, true);
        return opened.ok ? Result!Directory(adopt(opened.value)) : Result!Directory(Directory.init, opened.error);
    }

    /// Whether `path` (relative to the root, NUL-terminated) resolves beneath the root after following links.
    Error checkSymlink(ref const Directory root, string path) nothrow @nogc
    {
        const relative = path.length != 0 && path[$ - 1] == '\0' ? path[0 .. $ - 1] : path;
        if (relative.length == 0 || relative.length > 32_000 || root.path.length > 32_000)
            return Error(Status.invalidArgument, "invalid glob entry path");
        auto full = joinWide(root.path, relative);
        if (full is null)
            return Error(Status.invalidArgument, "invalid glob entry path");
        scope (exit)
            release(full);
        return resolvesBeneath(root.path, full);
    }

    // `root`, a separator and `relative` converted from UTF-8 with `/` as `\`, NUL-terminated, in a malloc buffer
    // the caller releases; null when the conversion fails or memory runs out.
    // SAFETY: Writes only inside the buffer of capacity root + 1 + relative + 1 units, which bounds the conversion.
    private wchar* joinWide(scope const(wchar)[] root, scope const(char)[] relative) @trusted nothrow @nogc
    {
        import core.stdc.stdlib : free, malloc;
        import core.sys.windows.winnls : CP_UTF8, MB_ERR_INVALID_CHARS, MultiByteToWideChar;

        auto full = cast(wchar*) malloc((root.length + relative.length + 2) * wchar.sizeof);
        if (full is null)
            return null;
        full[0 .. root.length] = root[];
        full[root.length] = '\\';
        auto tail = full + root.length + 1;
        const units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, relative.ptr,
                cast(int) relative.length, tail, cast(int) relative.length);
        if (units <= 0)
        {
            free(full);
            return null;
        }
        foreach (ref unit; tail[0 .. units])
            if (unit == '/')
                unit = '\\';
        tail[units] = 0;
        return full;
    }

    // SAFETY: Releases a buffer joinWide allocated.
    private void release(wchar* buffer) @trusted nothrow @nogc
    {
        import core.stdc.stdlib : free;

        free(buffer);
    }

    // Open `full` following links and check its final path lies beneath `root`.
    // SAFETY: `full` is NUL-terminated; the final path is written into a malloc buffer of the capacity passed,
    // which is freed, and the handle is closed, before returning.
    private Error resolvesBeneath(scope const(wchar)[] root, const(wchar)* full) @trusted nothrow @nogc
    {
        import core.stdc.stdlib : free, malloc;

        enum Error escaped = Error(Status.notFound, "entry no longer resolves inside glob root");
        auto handle = CreateFileW(full, readAttributes, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                null, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, null);
        if (handle == INVALID_HANDLE_VALUE)
            return escaped;
        scope (exit)
            CloseHandle(handle);
        enum DWORD capacity = 32_768;
        auto resolved = cast(wchar*) malloc(capacity * wchar.sizeof);
        if (resolved is null)
            return Error(Status.outOfMemory, "could not check glob entry");
        scope (exit)
            free(resolved);
        auto length = GetFinalPathNameByHandleW(handle, resolved, capacity, 0);
        if (length == 0 || length >= capacity)
            return escaped;
        while (length > 1 && resolved[length - 1] == '\\')
            --length;
        return beneath(root, resolved[0 .. length]) ? Error.init : escaped;
    }

    // SAFETY: One owned directory releases its search cursor and pinning handle once.
    void closeDirectory(ref Directory directory) @trusted nothrow @nogc
    {
        if (directory.cursor !is null)
            FindClose(directory.cursor);
        if (directory.handle !is null)
            CloseHandle(directory.handle);
        directory = Directory.init;
    }

    private EntryKind entryKind(ref const WIN32_FIND_DATAW data) pure nothrow @nogc
    {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0
                && (data.dwReserved0 == symlinkTag || data.dwReserved0 == junctionTag))
            return EntryKind.symlink;
        return (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ? EntryKind.directory : EntryKind.file;
    }

    /// The next entry, or an entry with a null name at the end of the directory.
    // SAFETY: The search writes one local WIN32_FIND_DATAW; its NUL-terminated name is bounded by the array and
    // copied before returning. The cursor is owned by the directory and closed by closeDirectory.
    @trusted Result!Entry nextEntry(ref Directory directory)
    {
        import std.utf : toUTF8;

        WIN32_FIND_DATAW data;
        if (directory.cursor is null)
        {
            auto pattern = directory.path ~ `\*`w ~ '\0';
            auto cursor = FindFirstFileExW(pattern.ptr, findExInfoBasic, &data,
                    findExSearchNameMatch, null, findFirstExLargeFetch);
            if (cursor == INVALID_HANDLE_VALUE)
            {
                const code = GetLastError();
                return code == ERROR_FILE_NOT_FOUND ? Result!Entry(Entry.init) : Result!Entry(Entry.init,
                        Error(nativeStatus(code), "could not read directory entry"));
            }
            directory.cursor = cursor;
        }
        else if (!FindNextFileW(directory.cursor, &data))
        {
            const code = GetLastError();
            return code == ERROR_NO_MORE_FILES ? Result!Entry(Entry.init) : Result!Entry(Entry.init,
                    Error(nativeStatus(code), "could not read directory entry"));
        }
        size_t length;
        while (length < data.cFileName.length && data.cFileName[length] != 0)
            ++length;
        if (length == 0 || length == data.cFileName.length)
            return Result!Entry(Entry.init, Error(Status.ioError, "invalid directory name record"));
        try
            return Result!Entry(Entry(toUTF8(data.cFileName[0 .. length]), entryKind(data)));
        catch (Exception)
            return Result!Entry(Entry.init, Error(Status.ioError, "invalid directory name record"));
    }
}
