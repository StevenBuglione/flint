// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.storage;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;
import flint.http : ChunkConsumer;

@safe:
struct Credentials
{
    string accessKeyId;
    string secretAccessKey;
    string sessionToken;
    long expiresAtUnixSeconds;
}

alias CredentialProvider = Result!Credentials delegate(ref Context context) @safe nothrow;
struct StorageOptions
{
    string endpoint;
    string region = "us-east-1";
    bool pathStyle = false;
    size_t partBytes = 8 * 1024 * 1024;
    uint concurrentParts = 4;
    bool verifyPeer = true;
}

struct ObjectInfo
{
    ulong size;
    Buffer etag;
    Buffer versionId;
}

struct Upload
{
    private ulong slot;
    private ulong generation;
    Error write(scope const(ubyte)[] chunk, ref Context context) nothrow @nogc;
    Result!ObjectInfo complete(ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error abort(ref Context context) nothrow @nogc;
}

struct ObjectStorage
{
    private ulong slot;
    private ulong generation;
    Error open(StorageOptions options, CredentialProvider credentials);
    Result!ObjectInfo head(string bucket, string key, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error get(string bucket, string key, scope ChunkConsumer consume, ref Context context) nothrow @nogc;
    Result!Upload beginUpload(string bucket, string key, string contentType, ref Context context) nothrow @nogc;
    Error remove(string bucket, string key, ref Context context) nothrow @nogc;
    Result!Buffer presignGet(string bucket, string key, uint expiresSeconds, long nowUnixSeconds,
            ref scope RequestArena arena) nothrow @nogc;
    Error close() nothrow @nogc;
}
