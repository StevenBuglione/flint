// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.security;
import flint.arena : Buffer, Error, RequestArena, Result, Text;
import flint.conc : Context;

@safe:
struct RolesAllowed
{
    string[] roles;
}

struct PreAuthorize
{
    string policy;
}

enum JwtAlgorithm : ubyte
{
    rs256,
    es256,
    eddsa
}

struct JwtPolicy
{
    string issuer;
    string audience;
    JwtAlgorithm[] algorithms;
    long clockSkewSeconds = 30;
    uint maxTokenBytes = 16384;
    bool requireExpiry = true;
}

struct Principal
{
    Text subject;
    Buffer roles;
    long expiresAtUnixSeconds;
}

struct JwtVerifier
{
    private ulong slot;
    private ulong generation;
    Error open(scope const ref JwtPolicy policy, string jwksUrl);
    Result!Principal verify(scope const(char)[] bearer, long nowUnixSeconds, ref scope RequestArena arena) nothrow @nogc;
    Error refresh(ref Context context) nothrow @nogc;
    Error close() nothrow @nogc;
}

struct CorsPolicy
{
    string[] origins;
    string[] methods;
    string[] headers;
    bool credentials = false;
    uint maxAgeSeconds = 600;
}

bool originAllowed(scope const ref CorsPolicy policy, scope const(char)[] origin) nothrow @nogc;
bool hasRole(scope const ref Principal principal, scope const(char)[] role, ref scope RequestArena arena) nothrow @nogc;
Error sha256(scope const(ubyte)[] input, ref ubyte[32] output) nothrow @nogc;
Error hmacSha256(scope const(ubyte)[] key, scope const(ubyte)[] input, ref ubyte[32] output) nothrow @nogc;
Result!Buffer hashPassword(scope const(ubyte)[] password, ref scope RequestArena arena, ref Context context) nothrow @nogc;
Result!bool verifyPassword(scope const(ubyte)[] password, scope const(char)[] encoded, ref Context context) nothrow @nogc;
