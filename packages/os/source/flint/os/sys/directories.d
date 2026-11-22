module flint.os.sys.directories;

import core.stdc.errno : EAGAIN, ELOOP, ENOENT, ENOTDIR, EXDEV, errno;
import core.sys.linux.unistd : syscall;
import core.sys.posix.dirent : DIR, DT_DIR, DT_LNK, DT_UNKNOWN, closedir, dirent, readdir;
import core.sys.posix.fcntl : O_CLOEXEC, O_DIRECTORY, O_RDONLY, open;
import core.sys.posix.sys.stat : fstat, stat_t;
import flint.arena : Error, Result, Status;
import flint.os.sys.process : closeFd, nativeStatus;

@safe:

package(flint.os):

private extern (C) DIR* fdopendir(int fd) @system nothrow @nogc;
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

// SAFETY: A live root fd anchors the kernel resolution. The local ABI struct and path are used synchronously.
private Result!int openBeneath(ref const Directory root, string path, ulong flags, bool follow) @trusted nothrow @nogc
{
    OpenHow how;
    how.flags = flags | O_CLOEXEC;
    how.resolve = beneathRoot | noMagicLinks | (follow ? 0 : noSymlinks);
    const fd = syscall(openat2Number, root.fd, path.ptr, &how, how.sizeof);
    if (fd >= 0)
        return Result!int(cast(int) fd);

    const code = errno;
    if (code == ELOOP || code == EXDEV || code == ENOTDIR || code == ENOENT || code == EAGAIN)
        return Result!int(-1, Error(Status.notFound, "entry no longer resolves inside glob root"));
    return Result!int(-1, Error(nativeStatus(code), "could not resolve entry under glob root"));
}

Result!Directory descend(ref const Directory root, string path, bool follow) nothrow @nogc
{
    const opened = openBeneath(root, path, O_RDONLY | O_DIRECTORY, follow);
    return opened.ok ? adopt(opened.value) : Result!Directory(Directory.init, opened.error);
}

Error checkSymlink(ref const Directory root, string path) nothrow @nogc
{
    auto opened = openBeneath(root, path, pathOnly, true);
    if (!opened.ok)
        return opened.error;
    closeFd(opened.value);
    return Error.init;
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
