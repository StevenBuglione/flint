// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.codec;
import flint.arena : Error, Result, Buffer, RequestArena;

@safe:
enum Codec : ubyte
{
    gzip,
    zstd,
    brotli
}

enum Finish : ubyte
{
    more,
    flush,
    end
}

struct CodecOptions
{
    Codec codec = Codec.gzip;
    int level = 3;
    ulong maxOutputBytes = 64 * 1024 * 1024;
    uint maxExpansionRatio = 100;
}

struct CodecStep
{
    size_t consumed;
    size_t produced;
    bool finished;
}

struct Encoder
{
    private ulong slot;
    private ulong generation;
    Error open(CodecOptions options);
    Result!CodecStep process(scope const(ubyte)[] input, scope ubyte[] output, Finish finish) nothrow @nogc;
    Error close() nothrow @nogc;
}

struct Decoder
{
    private ulong slot;
    private ulong generation;
    Error open(CodecOptions options);
    Result!CodecStep process(scope const(ubyte)[] input, scope ubyte[] output, Finish finish) nothrow @nogc;
    Error close() nothrow @nogc;
}

enum ArchiveFormat : ubyte
{
    zip,
    tar
}

struct ArchiveEntry
{
    Buffer path;
    ulong uncompressedBytes;
    bool directory;
}

alias ArchiveSource = Result!size_t delegate(scope ubyte[] output) @safe nothrow @nogc;
alias ArchiveSink = Error delegate(scope const(ubyte)[] input) @safe nothrow @nogc;
struct ArchiveOptions
{
    uint maxEntries = 10000;
    ulong maxTotalBytes = 1024UL * 1024 * 1024;
    size_t maxPathBytes = 4096;
    bool allowSymlinks = false;
}

struct ArchiveReader
{
    private ulong slot;
    private ulong generation;
    Error open(ArchiveFormat format, ArchiveOptions options, ArchiveSource source);
    Result!ArchiveEntry next(ref scope RequestArena arena) nothrow @nogc;
    Error read(scope ArchiveSink sink) nothrow @nogc;
    Error close() nothrow @nogc;
}

struct ArchiveWriter
{
    private ulong slot;
    private ulong generation;
    Error open(ArchiveFormat format, ArchiveSink sink);
    Error entry(scope const(char)[] relativePath, ulong size, bool directory) nothrow @nogc;
    Error write(scope const(ubyte)[] bytes) nothrow @nogc;
    Error close() nothrow @nogc;
}
