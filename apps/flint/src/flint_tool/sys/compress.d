/// gzip through Phobos' bundled zlib, whose class API is not annotated @safe.
module flint_tool.sys.compress;

@safe:

// SAFETY: Compress takes a private copy of the input and returns fresh GC arrays; nothing escapes or aliases.
/// gzip of `data` at the best compression level, with zlib's zero timestamp and no file name.
@trusted ubyte[] gzipBytes(scope const(ubyte)[] data)
{
    import std.zlib : Compress, HeaderFormat;

    auto compressor = new Compress(9, HeaderFormat.gzip);
    auto output = cast(ubyte[]) compressor.compress(data.dup);
    output ~= cast(ubyte[]) compressor.flush();
    return output;
}
