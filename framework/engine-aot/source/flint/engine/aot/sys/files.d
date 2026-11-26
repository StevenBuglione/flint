/++
The file system behind `flint.engine.aot.host`: one `stat`, a whole-file read and write, a directory's entry names,
the executable's path and the current directory.
Private to `flint:engine-aot`; applications never import it.

Paths arrive NUL-terminated (UTF-8 on POSIX, UTF-16 on Windows) from the facade, which refuses paths holding a
NUL of their own. Reads go into GC buffers the caller owns; nothing here keeps a pointer after it returns.
+/
module flint.engine.aot.sys.files;

@safe:

/// What a failed call reports, mapped from errno or the Windows error.
enum FileError
{
    none,
    notFound, /// ENOENT, ENOTDIR; ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, ERROR_INVALID_NAME
    accessDenied, /// EACCES, EPERM; ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION
    isDirectory, /// EISDIR
    other,
    resourceExhausted, /// The requested operation exceeds a host resource limit.
}

/// One `stat` of a path, following symbolic links.
struct FileFacts
{
    bool exists;
    bool regular; /// a regular file (on Windows: anything that is not a directory, as std.file.isFile)
    bool directory;
    long size;
    long modifiedTicks; /// 100 ns ticks since 1970-01-01T00:00Z, as std.datetime's stat conversion
}

package(flint) enum DirectoryEntryKind : ubyte
{
    other,
    file,
    directory,
    symlink,
}

package(flint) struct FileIdentity
{
    ulong device;
    ulong inode;
}

package(flint) struct DirectoryEntryFacts
{
    DirectoryEntryKind kind;
    FileIdentity identity;
}

version (Windows)
{
    import core.sys.windows.windef : BOOL, DWORD, HANDLE;
    import core.sys.windows.winbase : BY_HANDLE_FILE_INFORMATION, FILETIME,
        WIN32_FILE_ATTRIBUTE_DATA, WIN32_FIND_DATAW;

    private extern (Windows) nothrow @nogc
    {
        BOOL GetFileAttributesExW(scope const(wchar)* name, int level, void* information) @system;
        BOOL GetFileInformationByHandle(HANDLE file, BY_HANDLE_FILE_INFORMATION* information) @system;
        HANDLE CreateFileW(scope const(wchar)* name, DWORD access, DWORD share, void* security,
                DWORD disposition, DWORD flags, HANDLE template_) @system;
        BOOL ReadFile(HANDLE file, void* buffer, DWORD length, DWORD* read, void* overlapped) @system;
        BOOL CloseHandle(HANDLE handle) @system;
        DWORD GetCurrentDirectoryW(DWORD length, wchar* buffer) @system;
        DWORD GetLastError() @system;
        int MultiByteToWideChar(uint codePage, DWORD flags, scope const(char)* text, int length,
                wchar* wide, int wideLength) @system;
        int WideCharToMultiByte(uint codePage, DWORD flags, scope const(wchar)* wide, int wideLength,
                char* text, int length, const(char)* defaultChar, BOOL* usedDefault) @system;
    }

    /// An open file: a Windows handle, or null.
    alias FileHandle = HANDLE;

    private FileError mapError(DWORD error) nothrow @nogc
    {
        switch (error)
        {
        case 2, 3, 123: // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, ERROR_INVALID_NAME
            return FileError.notFound;
        case 5, 32: // ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION
            return FileError.accessDenied;
        default:
            return FileError.other;
        }
    }

    /// `text` as NUL-terminated UTF-16; null when it is not valid UTF-8 or is too long for Windows.
    // SAFETY: both calls read text.length bytes of text; the second writes at most wide.length units into the GC
    // buffer sized from the first call's count plus the NUL this function appends.
    @trusted wchar[] widen(scope const(char)[] text) nothrow
    {
        enum uint utf8 = 65_001, strict = 8; // CP_UTF8, MB_ERR_INVALID_CHARS
        if (text.length == 0)
            return ['\0'];
        if (text.length > int.max)
            return null;
        const length = MultiByteToWideChar(utf8, strict, &text[0], cast(int) text.length, null, 0);
        if (length <= 0)
            return null;
        auto wide = new wchar[](length + 1);
        if (MultiByteToWideChar(utf8, strict, &text[0], cast(int) text.length, &wide[0], length) != length)
            return null;
        wide[length] = '\0';
        return wide;
    }

    /// `wide` as UTF-8; unpaired surrogates become U+FFFD.
    // SAFETY: both calls read wide.length units of wide; the second writes at most text.length bytes into the GC
    // buffer sized from the first call's count.
    @trusted string narrow(scope const(wchar)[] wide) nothrow
    {
        enum uint utf8 = 65_001;
        if (wide.length == 0 || wide.length > int.max)
            return wide.length == 0 ? "" : null;
        const length = WideCharToMultiByte(utf8, 0, &wide[0], cast(int) wide.length, null, 0, null, null);
        if (length <= 0)
            return null;
        auto text = new char[](length);
        if (WideCharToMultiByte(utf8, 0, &wide[0], cast(int) wide.length, &text[0], length, null, null) != length)
            return null;
        return text.idup;
    }

    /// The facts about `pathz` (UTF-16, NUL-terminated); `exists` is false when Windows cannot read them.
    // SAFETY: pathz is NUL-terminated (checked); Windows writes only the local WIN32_FILE_ATTRIBUTE_DATA.
    @trusted FileFacts statPath(scope const(wchar)[] pathz) nothrow @nogc
    {
        enum ulong unixEpoch = 116_444_736_000_000_000; // 1970-01-01 in FILETIME ticks since 1601-01-01
        FileFacts facts;
        WIN32_FILE_ATTRIBUTE_DATA data;
        if (pathz.length == 0 || pathz[$ - 1] != '\0' || !GetFileAttributesExW(&pathz[0], 0, &data))
            return facts;
        facts.exists = true;
        facts.directory = (data.dwFileAttributes & 0x10) != 0; // FILE_ATTRIBUTE_DIRECTORY
        facts.regular = !facts.directory;
        facts.size = cast(long)((cast(ulong) data.nFileSizeHigh << 32) | data.nFileSizeLow);
        const written = (cast(ulong) data.ftLastWriteTime.dwHighDateTime << 32) | data.ftLastWriteTime.dwLowDateTime;
        facts.modifiedTicks = cast(long) written - cast(long) unixEpoch;
        return facts;
    }

    /// The kind and identity of a directory entry. Reparse points are returned as links.
    // SAFETY: The checked NUL-terminated path is used synchronously. The call writes one local information record
    // and scope(exit) closes the owned handle on every path after opening it.
    @trusted FileError directoryEntryFacts(scope const(wchar)[] pathz, out DirectoryEntryFacts facts) nothrow @nogc
    {
        import core.sys.windows.winbase : FILE_FLAG_BACKUP_SEMANTICS, FILE_FLAG_OPEN_REPARSE_POINT,
            INVALID_HANDLE_VALUE, OPEN_EXISTING;
        import core.sys.windows.winnt : FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT,
            FILE_READ_ATTRIBUTES, FILE_SHARE_DELETE, FILE_SHARE_READ, FILE_SHARE_WRITE;

        if (pathz.length == 0 || pathz[$ - 1] != '\0')
            return FileError.notFound;
        auto handle = CreateFileW(&pathz[0], FILE_READ_ATTRIBUTES,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                null, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, null);
        if (handle == INVALID_HANDLE_VALUE)
            return mapError(GetLastError());
        scope (exit)
            CloseHandle(handle);
        BY_HANDLE_FILE_INFORMATION info;
        if (!GetFileInformationByHandle(handle, &info))
            return mapError(GetLastError());
        if (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
            facts.kind = DirectoryEntryKind.symlink;
        else
            facts.kind = (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                ? DirectoryEntryKind.directory : DirectoryEntryKind.file;
        facts.identity = FileIdentity(info.dwVolumeSerialNumber,
                (cast(ulong) info.nFileIndexHigh << 32) | info.nFileIndexLow);
        return FileError.none;
    }

    /// `pathz` (UTF-16, NUL-terminated) opened for reading; null with `error` set when it cannot be.
    // SAFETY: pathz is NUL-terminated (checked); CreateFileW reads only the name.
    @trusted FileHandle openRead(scope const(wchar)[] pathz, out FileError error) nothrow @nogc
    {
        enum DWORD genericRead = 0x8000_0000, shareRead = 1, openExisting = 3, sequential = 0x0800_0000;
        enum HANDLE invalid = cast(HANDLE)-1;
        if (pathz.length == 0 || pathz[$ - 1] != '\0')
        {
            error = FileError.notFound;
            return null;
        }
        auto handle = CreateFileW(&pathz[0], genericRead, shareRead, null, openExisting, sequential, null);
        if (handle is invalid || handle is null)
        {
            error = mapError(GetLastError());
            return null;
        }
        return handle;
    }

    /// Up to `buffer.length` bytes read from `file` into `buffer`: the count, 0 at the end, -1 on failure.
    // SAFETY: ReadFile writes at most the DWORD-capped buffer.length bytes into buffer, which the caller owns.
    @trusted ptrdiff_t readInto(FileHandle file, scope ubyte[] buffer) nothrow @nogc
    {
        if (file is null || buffer.length == 0)
            return -1;
        DWORD read;
        const length = buffer.length > DWORD.max ? DWORD.max : cast(DWORD) buffer.length;
        return ReadFile(file, &buffer[0], length, &read, null) ? read : -1;
    }

    /// Close a handle `openRead` returned.
    // SAFETY: CloseHandle takes the handle by value; a null handle is never passed.
    @trusted void closeFile(FileHandle file) nothrow @nogc
    {
        if (file !is null)
            CloseHandle(file);
    }

    /// The current directory written into `buffer` (UTF-16, no NUL): the length written, or the length the buffer
    /// needs (more than buffer.length) when it is too small, or 0 on failure.
    // SAFETY: GetCurrentDirectoryW writes at most buffer.length units, NUL included, into buffer.
    @trusted size_t currentDirectoryInto(scope wchar[] buffer) nothrow @nogc
    {
        if (buffer.length == 0 || buffer.length > DWORD.max)
            return 0;
        const length = GetCurrentDirectoryW(cast(DWORD) buffer.length, &buffer[0]);
        return length < buffer.length ? length : length + 1;
    }

    /// An open directory listing: the search handle and the entry it found but has not given yet.
    struct DirectoryHandle
    {
        private HANDLE search;
        private WIN32_FIND_DATAW found;
        private bool pending;
    }

    /// The listing of `pathz` (UTF-16 `directory\*`, NUL-terminated); false with `error` set when it cannot be
    /// opened.
    // SAFETY: pathz is NUL-terminated (checked); FindFirstFileW writes only the handle's WIN32_FIND_DATAW.
    @trusted bool openDirectory(scope const(wchar)[] pathz, out DirectoryHandle dir, out FileError error) nothrow @nogc
    {
        import core.sys.windows.winbase : FindFirstFileW, INVALID_HANDLE_VALUE;

        if (pathz.length == 0 || pathz[$ - 1] != '\0')
        {
            error = FileError.notFound;
            return false;
        }
        dir.search = FindFirstFileW(&pathz[0], &dir.found);
        if (dir.search == INVALID_HANDLE_VALUE)
        {
            error = mapError(GetLastError());
            return false;
        }
        dir.pending = true;
        return true;
    }

    /// The next entry's name (UTF-8, `.` and `..` included), or null at the end or on failure.
    // SAFETY: cFileName is a fixed MAX_PATH array; the name is read only up to its NUL, found within the array;
    // FindNextFileW writes only the handle's WIN32_FIND_DATAW.
    @trusted string nextEntryName(ref DirectoryHandle directory, out FileError error) nothrow
    {
        import core.sys.windows.winbase : FindNextFileW;

        if (directory.search is null)
            return null;
        if (!directory.pending && !FindNextFileW(directory.search, &directory.found))
        {
            const code = GetLastError();
            if (code != 18) // ERROR_NO_MORE_FILES
                error = mapError(code);
            return null;
        }
        directory.pending = false;
        size_t length;
        while (length < directory.found.cFileName.length && directory.found.cFileName[length] != 0)
            length++;
        auto name = narrow(directory.found.cFileName[0 .. length]);
        return name is null ? "" : name;
    }

    /// Close a listing `openDirectory` opened.
    // SAFETY: FindClose takes the handle by value; it is passed once, then forgotten.
    @trusted void closeDirectory(ref DirectoryHandle directory) nothrow @nogc
    {
        import core.sys.windows.winbase : FindClose;

        if (directory.search !is null)
            FindClose(directory.search);
        directory.search = null;
    }

    /// `pathz` (UTF-16, NUL-terminated) created or truncated for writing; null with `error` set when it cannot be.
    // SAFETY: pathz is NUL-terminated (checked); CreateFileW reads only the name.
    @trusted FileHandle openWrite(scope const(wchar)[] pathz, out FileError error) nothrow @nogc
    {
        enum DWORD genericWrite = 0x4000_0000, createAlways = 2, normal = 0x80;
        if (pathz.length == 0 || pathz[$ - 1] != '\0')
        {
            error = FileError.notFound;
            return null;
        }
        auto file = CreateFileW(&pathz[0], genericWrite, 0, null, createAlways, normal, null);
        if (file == cast(HANDLE)-1)
        {
            error = mapError(GetLastError());
            return null;
        }
        return file;
    }

    /// Up to `bytes.length` bytes written from `bytes` to `file`: the count, or -1 on failure.
    // SAFETY: WriteFile reads at most bytes.length bytes of bytes and writes only the local count.
    @trusted ptrdiff_t writeFrom(FileHandle file, scope const(ubyte)[] bytes) nothrow @nogc
    {
        import core.sys.windows.winbase : WriteFile;

        if (file is null || bytes.length == 0)
            return -1;
        DWORD written;
        const length = cast(DWORD)(bytes.length > int.max ? int.max : bytes.length);
        return WriteFile(file, &bytes[0], length, &written, null) ? cast(ptrdiff_t) written : -1;
    }

    /// The running executable's path as UTF-16 (no NUL), or null.
    // SAFETY: GetModuleFileNameW writes at most buffer.length units into the GC buffer and returns the count.
    @trusted wchar[] executablePathWide() nothrow
    {
        import core.sys.windows.winbase : GetModuleFileNameW;

        for (DWORD size = 260; size <= 32_768; size *= 2)
        {
            auto buffer = new wchar[](size);
            const length = GetModuleFileNameW(null, &buffer[0], size);
            if (length == 0)
                return null;
            if (length < size)
                return buffer[0 .. length];
        }
        return null;
    }
}
else version (Posix)
{
    import core.stdc.errno : EACCES, EINTR, EISDIR, ENOENT, ENOTDIR, EPERM, errno;
    import core.sys.posix.fcntl : O_RDONLY, open;

    version (OSX)
        private enum int O_CLOEXEC = 0x0100_0000; // <sys/fcntl.h>; druntime does not declare it for macOS
    else
        import core.sys.posix.fcntl : O_CLOEXEC;
    import core.sys.posix.dirent : closedir, DIR, opendir, readdir;
    import core.sys.posix.sys.stat : lstat, S_IFDIR, S_IFLNK, S_IFMT, S_IFREG, stat, stat_t;
    import core.sys.posix.unistd : close, getcwd, read;

    /// An open file: a descriptor, or -1.
    alias FileHandle = int;

    private FileError mapError(int code) nothrow @nogc
    {
        if (code == ENOENT || code == ENOTDIR)
            return FileError.notFound;
        if (code == EACCES || code == EPERM)
            return FileError.accessDenied;
        return code == EISDIR ? FileError.isDirectory : FileError.other;
    }

    /// The facts about `pathz` (NUL-terminated); `exists` is false when stat fails.
    // SAFETY: pathz is NUL-terminated (checked); stat writes only the local stat_t.
    @trusted FileFacts statPath(scope const(char)[] pathz) nothrow @nogc
    {
        FileFacts facts;
        stat_t buffer;
        if (pathz.length == 0 || pathz[$ - 1] != '\0' || stat(&pathz[0], &buffer) != 0)
            return facts;
        facts.exists = true;
        facts.regular = (buffer.st_mode & S_IFMT) == S_IFREG;
        facts.directory = (buffer.st_mode & S_IFMT) == S_IFDIR;
        facts.size = cast(long) buffer.st_size;
        // Seconds and nanoseconds as std.file's statTimeToStdTime reads them; the druntime st_mtime accessor
        // is not @nogc, so the fields are read directly.
        long seconds, nanoseconds;
        static if (is(typeof(buffer.st_mtim.tv_nsec)))
        {
            seconds = buffer.st_mtim.tv_sec;
            nanoseconds = buffer.st_mtim.tv_nsec;
        }
        else static if (is(typeof(buffer.st_mtimespec.tv_nsec)))
        {
            seconds = buffer.st_mtimespec.tv_sec;
            nanoseconds = buffer.st_mtimespec.tv_nsec;
        }
        else
        {
            seconds = buffer.st_mtime;
            static if (is(typeof(buffer.st_mtimensec)))
                nanoseconds = buffer.st_mtimensec;
        }
        facts.modifiedTicks = seconds * 10_000_000 + nanoseconds / 100;
        return facts;
    }

    /// The kind and identity of a directory entry obtained from lstat.
    // SAFETY: The checked NUL-terminated path is used synchronously and lstat writes only the local stat record.
    @trusted FileError directoryEntryFacts(scope const(char)[] pathz, out DirectoryEntryFacts facts) nothrow @nogc
    {
        if (pathz.length == 0 || pathz[$ - 1] != '\0')
            return FileError.notFound;
        stat_t info;
        if (lstat(&pathz[0], &info) != 0)
            return mapError(errno);
        switch (info.st_mode & S_IFMT)
        {
        case S_IFREG:
            facts.kind = DirectoryEntryKind.file;
            break;
        case S_IFDIR:
            facts.kind = DirectoryEntryKind.directory;
            break;
        case S_IFLNK:
            facts.kind = DirectoryEntryKind.symlink;
            break;
        default:
            break;
        }
        facts.identity = FileIdentity(cast(ulong) info.st_dev, cast(ulong) info.st_ino);
        return FileError.none;
    }

    /// `pathz` (NUL-terminated) opened for reading; -1 with `error` set when it cannot be.
    // SAFETY: pathz is NUL-terminated (checked); open reads only the name.
    @trusted FileHandle openRead(scope const(char)[] pathz, out FileError error) nothrow @nogc
    {
        if (pathz.length == 0 || pathz[$ - 1] != '\0')
        {
            error = FileError.notFound;
            return -1;
        }
        int descriptor;
        do
            descriptor = open(&pathz[0], O_RDONLY | O_CLOEXEC);
        while (descriptor < 0 && errno == EINTR);
        if (descriptor < 0)
            error = mapError(errno);
        return descriptor;
    }

    /// Up to `buffer.length` bytes read from `file` into `buffer`: the count, 0 at the end, -1 on failure.
    // SAFETY: read writes at most buffer.length bytes into buffer, which the caller owns.
    @trusted ptrdiff_t readInto(FileHandle file, scope ubyte[] buffer) nothrow @nogc
    {
        if (file < 0 || buffer.length == 0)
            return -1;
        ptrdiff_t count;
        do
            count = read(file, &buffer[0], buffer.length);
        while (count < 0 && errno == EINTR);
        return count;
    }

    /// Close a descriptor `openRead` returned.
    // SAFETY: close takes the descriptor by value; a negative one is never passed.
    @trusted void closeFile(FileHandle file) nothrow @nogc
    {
        if (file >= 0)
            close(file);
    }

    /// The current directory written into `buffer` (no NUL): the length written, buffer.length + 1 when the
    /// buffer is too small, or 0 on any other failure.
    // SAFETY: getcwd writes at most buffer.length bytes, NUL included, into buffer; the NUL is found within it.
    @trusted size_t currentDirectoryInto(scope char[] buffer) nothrow @nogc
    {
        import core.stdc.errno : ERANGE;

        if (buffer.length == 0)
            return 0;
        if (getcwd(&buffer[0], buffer.length) is null)
            return errno == ERANGE ? buffer.length + 1 : 0;
        foreach (i, c; buffer)
            if (c == '\0')
                return i;
        return 0;
    }

    /// An open directory listing, or null.
    struct DirectoryHandle
    {
        private DIR* stream;
    }

    /// The listing of `pathz` (NUL-terminated); false with `error` set when it cannot be opened.
    // SAFETY: pathz is NUL-terminated (checked); opendir reads only the name and returns a stream this module owns
    // until closeDirectory.
    @trusted bool openDirectory(scope const(char)[] pathz, out DirectoryHandle dir, out FileError error) nothrow @nogc
    {
        if (pathz.length == 0 || pathz[$ - 1] != '\0')
        {
            error = FileError.notFound;
            return false;
        }
        dir.stream = opendir(&pathz[0]);
        if (dir.stream is null)
        {
            error = mapError(errno);
            return false;
        }
        return true;
    }

    /// The next entry's name (`.` and `..` included), copied to the GC, or null at the end or on failure.
    // SAFETY: readdir returns an entry valid until the next readdir or closedir on this stream; its d_name is
    // NUL-terminated (POSIX), so strlen stays within it, and the name is copied before returning.
    @trusted string nextEntryName(ref DirectoryHandle directory, out FileError error) nothrow
    {
        import core.stdc.string : strlen;

        if (directory.stream is null)
            return null;
        errno = 0;
        const entry = readdir(directory.stream);
        if (entry is null)
        {
            if (errno != 0)
                error = mapError(errno);
            return null;
        }
        const name = entry.d_name.ptr;
        return name[0 .. strlen(name)].idup;
    }

    /// Close a listing `openDirectory` opened.
    // SAFETY: closedir takes the stream once; it is forgotten after, so no entry or stream pointer outlives it.
    @trusted void closeDirectory(ref DirectoryHandle directory) nothrow @nogc
    {
        if (directory.stream !is null)
            closedir(directory.stream);
        directory.stream = null;
    }

    /// `pathz` (NUL-terminated) created or truncated for writing (mode 0666 before the umask); -1 with `error` set
    /// when it cannot be.
    // SAFETY: pathz is NUL-terminated (checked); open reads only the name.
    @trusted FileHandle openWrite(scope const(char)[] pathz, out FileError error) nothrow @nogc
    {
        import core.sys.posix.fcntl : O_CREAT, O_TRUNC, O_WRONLY;

        if (pathz.length == 0 || pathz[$ - 1] != '\0')
        {
            error = FileError.notFound;
            return -1;
        }
        int descriptor;
        do
            descriptor = open(&pathz[0], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0x1B6); // 0666
        while (descriptor < 0 && errno == EINTR);
        if (descriptor < 0)
            error = mapError(errno);
        return descriptor;
    }

    /// Up to `bytes.length` bytes written from `bytes` to `file`: the count, or -1 on failure.
    // SAFETY: write reads at most bytes.length bytes of bytes, which the caller owns.
    @trusted ptrdiff_t writeFrom(FileHandle file, scope const(ubyte)[] bytes) nothrow @nogc
    {
        import core.sys.posix.unistd : write;

        if (file < 0 || bytes.length == 0)
            return -1;
        ptrdiff_t count;
        do
            count = write(file, &bytes[0], bytes.length);
        while (count < 0 && errno == EINTR);
        return count;
    }

    /// The running executable's path written into `buffer` (no NUL): the length, buffer.length + 1 when the buffer
    /// is too small, or 0 when it cannot be read (Linux's /proc/self/exe, macOS's _NSGetExecutablePath).
    // SAFETY: readlink writes at most buffer.length bytes into buffer and returns the count it wrote;
    // _NSGetExecutablePath writes at most size bytes, NUL included, and the NUL is found within buffer.
    @trusted size_t executablePathInto(scope char[] buffer) nothrow @nogc
    {
        if (buffer.length == 0)
            return 0;
        version (linux)
        {
            import core.sys.posix.unistd : readlink;

            const length = readlink("/proc/self/exe", &buffer[0], buffer.length);
            if (length <= 0)
                return 0;
            return cast(size_t) length < buffer.length ? cast(size_t) length : buffer.length + 1;
        }
        else version (OSX)
        {
            static extern (C) int _NSGetExecutablePath(char* buffer, uint* size) nothrow @nogc @system;

            uint size = buffer.length > uint.max ? uint.max : cast(uint) buffer.length;
            if (_NSGetExecutablePath(&buffer[0], &size) != 0)
                return buffer.length + 1;
            foreach (i, c; buffer)
                if (c == '\0')
                    return i;
            return 0;
        }
        else
            static assert(0, "flint.engine.aot.sys.files: no executable path for this platform");
    }
}
else
    static assert(0, "flint.engine.aot.sys.files: unsupported platform");

/// The next name for callers that treat any read error as the end of the listing.
string nextEntryName(ref DirectoryHandle directory) nothrow
{
    FileError ignored;
    return nextEntryName(directory, ignored);
}

@("entry metadata rejects an invalid or missing path")
unittest
{
    import std.conv : to;
    import std.file : tempDir;
    import std.path : buildPath;
    import std.process : thisProcessID;

    const missing = buildPath(tempDir(), "flint-directory-entry-absent-" ~ thisProcessID.to!string);
    version (Windows)
        const pathz = widen(missing);
    else
        const pathz = missing ~ '\0';
    DirectoryEntryFacts facts;
    assert(directoryEntryFacts(pathz[0 .. $ - 1], facts) == FileError.notFound);
    assert(directoryEntryFacts(pathz, facts) == FileError.notFound);
    assert(facts.kind == DirectoryEntryKind.other && facts.identity == FileIdentity.init);
}

version (Posix) unittest
{
    import std.file : remove, tempDir, write;

    // Positive: a regular file's facts and bytes, and a directory.
    const path = tempDir ~ "/flint-sys-files-test";
    write(path, "abc");
    scope (exit)
        remove(path);
    const file = statPath(path ~ '\0');
    assert(file.exists && file.regular && !file.directory && file.size == 3 && file.modifiedTicks > 0);
    const directory = statPath(tempDir ~ '\0');
    assert(directory.exists && directory.directory && !directory.regular);
    FileError error;
    auto handle = openRead(path ~ '\0', error);
    assert(handle >= 0 && error == FileError.none);
    ubyte[8] bytes;
    assert(readInto(handle, bytes[]) == 3 && bytes[0 .. 3] == "abc");
    assert(readInto(handle, bytes[]) == 0);
    closeFile(handle);
    char[4096] cwd;
    const length = currentDirectoryInto(cwd[]);
    assert(length > 0 && length < cwd.length && cwd[0] == '/');

    // Negative: missing paths, names without their NUL, a closed descriptor, a buffer too small for the directory.
    assert(!statPath(path ~ ".missing\0").exists);
    assert(!statPath(path).exists && !statPath("").exists);
    assert(openRead(path ~ ".missing\0", error) < 0 && error == FileError.notFound);
    assert(openRead(path, error) < 0 && error == FileError.notFound);
    assert(readInto(-1, bytes[]) == -1 && readInto(handle, bytes[0 .. 0]) == -1);
    char[1] tiny;
    assert(currentDirectoryInto(tiny[]) == 2 && currentDirectoryInto(tiny[0 .. 0]) == 0);
}

version (Posix) unittest
{
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import std.conv : to;

    const root = buildPath(tempDir, "flint-aot-files-dir-" ~ thisProcessID.to!string);
    mkdirRecurse(buildPath(root, "sub"));
    scope (exit)
        rmdirRecurse(root);
    write(buildPath(root, "file"), "x");
    DirectoryHandle directory;
    FileError error;
    assert(openDirectory(root ~ '\0', directory, error) && error == FileError.none);
    string[] names;
    for (auto name = nextEntryName(directory); name !is null; name = nextEntryName(directory))
        names ~= name;
    closeDirectory(directory);
    closeDirectory(directory); // a second close does nothing
    assert(nextEntryName(directory) is null);
    import std.algorithm.sorting : sort;

    names.sort();
    assert(names == [".", "..", "file", "sub"], names.to!string);

    assert(!openDirectory(root ~ "/missing\0", directory, error) && error == FileError.notFound);
    assert(!openDirectory(buildPath(root, "file") ~ '\0', directory, error) && error == FileError.notFound);
    assert(!openDirectory(root, directory, error) && error == FileError.notFound); // no NUL
    assert(!openDirectory("", directory, error));
}

version (Posix) unittest
{
    import std.conv : to;
    import std.file : read, readText, remove, tempDir, thisExePath;
    import std.process : thisProcessID;

    // Write, positive: create, then truncate; the bytes read back.
    const path = tempDir ~ "/flint-aot-files-write-" ~ thisProcessID.to!string;
    FileError error;
    foreach (content; ["first content", "second"])
    {
        auto file = openWrite(path ~ '\0', error);
        assert(file >= 0 && error == FileError.none);
        assert(writeFrom(file, cast(const(ubyte)[]) content) == content.length);
        closeFile(file);
        assert(readText(path) == content);
    }
    remove(path);
    // Write, negative: a missing directory, a directory, no NUL, nothing to write or no file.
    assert(openWrite(path ~ "/missing/x\0", error) < 0 && error == FileError.notFound);
    assert(openWrite(tempDir ~ '\0', error) < 0 && error == FileError.isDirectory);
    assert(openWrite(path, error) < 0 && error == FileError.notFound);
    assert(writeFrom(-1, [1]) == -1 && writeFrom(0, null) == -1);

    // The executable, as std.file's thisExePath; a buffer too small says so, an empty one gives 0.
    version (linux)
    {
        char[4096] buffer;
        const length = executablePathInto(buffer[]);
        assert(length > 0 && length <= buffer.length && buffer[0 .. length] == thisExePath());
        char[2] tiny;
        assert(executablePathInto(tiny[]) == tiny.length + 1 && executablePathInto(tiny[0 .. 0]) == 0);
    }
}
