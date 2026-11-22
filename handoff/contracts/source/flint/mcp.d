// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.mcp;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct McpTool
{
    string name;
    string description;
    bool readOnly = false;
}

struct McpResource
{
    string uri;
    string mimeType = "text/plain";
}

enum ProtocolRevision : ubyte
{
    modern20260728,
    legacy20251125
}

enum Transport : ubyte
{
    stdio,
    streamableHttp
}

struct McpOptions
{
    string name;
    string versionString;
    ProtocolRevision revision = ProtocolRevision.modern20260728;
    bool acceptLegacy = true;
    Transport transport = Transport.stdio;
    string address = "127.0.0.1";
    ushort port = 3000;
    string path = "/mcp";
    size_t maxMessageBytes = 4 * 1024 * 1024;
    uint maxInFlight = 64;
    string[] allowedOrigins;
}

struct ToolResult
{
    Buffer content;
    Buffer structuredContent;
    bool isError = false;
}

struct McpServer
{
    private ulong slot;
    private ulong generation;
    Error open(McpOptions options);
    Error run(ref Context context) nothrow @nogc;
    Error close(ref Context context) nothrow @nogc;
}

struct McpClient
{
    private ulong slot;
    private ulong generation;
    Error connect(string endpoint, ProtocolRevision revision, ref Context context);
    Result!Buffer listTools(ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!ToolResult callTool(string name, scope const(ubyte)[] arguments,
            ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!Buffer readResource(string uri, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error close(ref Context context) nothrow @nogc;
}

Error registerMcp(T)(ref McpServer server, ref T provider);
