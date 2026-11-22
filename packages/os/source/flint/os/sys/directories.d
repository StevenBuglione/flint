module flint.os.sys.directories;

import core.stdc.errno : EAGAIN, ELOOP, ENOENT, ENOTDIR, EXDEV, errno;
import core.sys.posix.dirent : DIR, DT_DIR, DT_LNK, DT_UNKNOWN, closedir, dirent, readdir;
import core.sys.posix.fcntl : O_RDONLY, open;
import core.sys.posix.sys.stat : fstat, stat_t;
import flint.arena : Error, Result, Status;
import flint.os.sys.process : closeFd, nativeStatus;

@safe:

package(flint.os):

private extern (C) DIR* fdopendir(int fd) @system nothrow @nogc;

version (OSX)
{
    // <sys/fcntl.h>. druntime omits O_CLOEXEC and O_DIRECTORY for Darwin. O_RESOLVE_BENEATH and
    // O_NOFOLLOW_ANY give openat the containment openat2's RESOLVE_BENEATH and RESOLVE_NO_SYMLINKS
    // give on Linux; Darwin has no magic links. An escape fails with ENOTCAPABLE instead of EXDEV.
    private enum int O_CLOEXEC = 0x0100_0000;
    private enum int O_DIRECTORY = 0x0010_0000;
    private enum int resolveBeneath = 0x0000_1000; // O_RESOLVE_BENEATH
    private enum int noSymlinksAnywhere = 0x2000_0000; // O_NOFOLLOW_ANY
    private enum int atResolveBeneath = 0x2000; // AT_RESOLVE_BENEATH
    private enum int notCapable = 107; // ENOTCAPABLE
    private extern (C) @system nothrow @nogc
    {
        int openat(int directory, scope const(char)* path, int flags, ...);
        int fstatat(int directory, scope const(char)* path, stat_t* details, int flags);
    }
}
else
{
    import core.sys.linux.unistd : syscall;
    import core.sys.posix.fcntl : O_CLOEXEC, O_DIRECTORY;

    private enum long openat2Number = 437;
    private enum ulong pathOnly = 0x20_0000;
    private enum ulong noMagicLinks = 0x02;
    private enum ulong noSymlinks = 0x04;
    private enum ulong beneathRoot = 0x08;

    private struct OpenHow
    {
        ulong flags;
        ulong mode;
        ulong resolve;
    }
}

struct FileIdentity
{
    ulong device;
    ulong inode;
}

struct Directory
{
    private DIR* cursor;
    private int fd = -1;
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

// SAFETY: fdopendir takes the directory fd on success. Every failure closes the original owner.
private Result!Directory adopt(int fd) @trusted nothrow @nogc
{
    stat_t details;
    if (fstat(fd, &details) != 0)
    {
        const status = nativeStatus(errno);
        closeFd(fd);
        return Result!Directory(Directory.init, Error(status, "could not identify directory"));
    }
    auto cursor = fdopendir(fd);
    if (cursor is null)
    {
        const status = nativeStatus(errno);
        closeFd(fd);
        return Result!Directory(Directory.init, Error(status, "could not open directory cursor"));
    }
    return Result!Directory(Directory(cursor, fd, FileIdentity(details.st_dev, details.st_ino)));
}

// SAFETY: The path has a validated terminal NUL and open never retains it.
Result!Directory openRoot(string terminatedPath) @trusted nothrow @nogc
{
    const fd = open(terminatedPath.ptr, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0)
        return Result!Directory(Directory.init, Error(nativeStatus(errno), "could not open glob root"));
    return adopt(fd);
}

// An entry that no longer resolves inside the root is absent, not a failure.
private Error beneathError(int code) nothrow @nogc
{
    version (OSX)
        const escaped = code == notCapable;
    else
        const escaped = false;
    if (escaped || code == ELOOP || code == EXDEV || code == ENOTDIR || code == ENOENT || code == EAGAIN)
        return Error(Status.notFound, "entry no longer resolves inside glob root");
    return Error(nativeStatus(code), "could not resolve entry under glob root");
}

version (OSX)
{
    // SAFETY: A live root fd anchors the kernel resolution. The terminated path is used synchronously.
    private Result!int openBeneath(ref const Directory root, string path, int flags, bool follow) @trusted nothrow @nogc
    {
        const fd = openat(root.fd, path.ptr, flags | O_CLOEXEC | resolveBeneath | (follow ? 0 : noSymlinksAnywhere));
        return fd >= 0 ? Result!int(fd) : Result!int(-1, beneathError(errno));
    }

    // SAFETY: fstatat writes one local stat_t. A live root fd anchors the kernel resolution and the
    // terminated path is used synchronously. Like O_PATH, it needs only search permission.
    private Error resolvesBeneath(ref const Directory root, string path) @trusted nothrow @nogc
    {
        stat_t details;
        return fstatat(root.fd, path.ptr, &details, atResolveBeneath) == 0 ? Error.init : beneathError(errno);
    }
}
else
{
    // SAFETY: A live root fd anchors the kernel resolution. The local ABI struct and path are used synchronously.
    @trusted private Result!int openBeneath(ref const Directory root, string path, ulong mode, bool links) nothrow @nogc
    {
        OpenHow how;
        how.flags = mode | O_CLOEXEC;
        how.resolve = beneathRoot | noMagicLinks | (links ? 0 : noSymlinks);
        const fd = syscall(openat2Number, root.fd, path.ptr, &how, how.sizeof);
        if (fd >= 0)
            return Result!int(cast(int) fd);
        return Result!int(-1, beneathError(errno));
    }
}

Result!Directory descend(ref const Directory root, string path, bool follow) nothrow @nogc
{
    const opened = openBeneath(root, path, O_RDONLY | O_DIRECTORY, follow);
    return opened.ok ? adopt(opened.value) : Result!Directory(Directory.init, opened.error);
}

Error checkSymlink(ref const Directory root, string path) nothrow @nogc
{
    version (OSX)
        return resolvesBeneath(root, path);
    else
    {
        auto opened = openBeneath(root, path, pathOnly, true);
        if (!opened.ok)
            return opened.error;
        closeFd(opened.value);
        return Error.init;
    }
}

// SAFETY: One owned DIR cursor is closed once. closedir also releases the adopted descriptor.
void closeDirectory(ref Directory directory) @trusted nothrow @nogc
{
    if (directory.cursor !is null)
    {
        closedir(directory.cursor);
        directory = Directory.init;
    }
}

private EntryKind entryKind(ubyte value) pure nothrow @nogc
{
    switch (value)
    {
    case DT_DIR:
        return EntryKind.directory;
    case DT_LNK:
        return EntryKind.symlink;
    case DT_UNKNOWN:
        return EntryKind.unknown;
    default:
        return EntryKind.file;
    }
}

// SAFETY: readdir's row is borrowed from one cursor. The record length bounds the copied NUL-delimited name.
@trusted Result!Entry nextEntry(ref Directory directory)
{
    errno = 0;
    const row = readdir(directory.cursor);
    if (row is null)
        return errno == 0 ? Result!Entry(Entry.init) : Result!Entry(Entry.init,
                Error(nativeStatus(errno), "could not read directory entry"));

    enum offset = dirent.d_name.offsetof;
    if (row.d_reclen <= offset)
        return Result!Entry(Entry.init, Error(Status.ioError, "invalid directory record"));
    const available = row.d_reclen - offset;
    const limit = available < row.d_name.length ? available : row.d_name.length;
    size_t length;
    while (length < limit && row.d_name[length] != '\0')
        ++length;
    if (length == 0 || length == limit)
        return Result!Entry(Entry.init, Error(Status.ioError, "invalid directory name record"));
    return Result!Entry(Entry(row.d_name[0 .. length].idup, entryKind(row.d_type)));
}
