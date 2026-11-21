// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.ai;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct Tool
{
    string name;
    string description;
}

enum Provider : ubyte
{
    openAI,
    anthropic,
    gemini,
    openRouter
}

enum Role : ubyte
{
    system,
    user,
    assistant,
    tool
}

enum EventKind : ubyte
{
    textDelta,
    toolDelta,
    usage,
    completed,
    failed
}

struct ChatMessage
{
    Role role;
    Buffer content;
    string toolCallId;
}

struct ChatOptions
{
    string model;
    uint maxOutputTokens = 1024;
    double temperature = 0;
    uint maxToolRounds = 8;
    size_t maxEventBytes = 1024 * 1024;
}

struct ChatEvent
{
    EventKind kind;
    Buffer text;
    string toolCallId;
    uint inputTokens;
    uint outputTokens;
}

alias EventConsumer = Error delegate(ref ChatEvent event, ref scope RequestArena arena) @safe nothrow @nogc;
struct AiOptions
{
    Provider provider;
    string baseUrl;
    string apiKey;
    string apiVersion;
    uint maxConcurrentRequests = 32;
}

struct ChatClient
{
    private ulong slot;
    private ulong generation;
    Error open(AiOptions options);
    Error stream(scope const(ChatMessage)[] messages, ChatOptions options, ref scope RequestArena arena,
            ref Context context, scope EventConsumer consume) nothrow @nogc;
    Error close() nothrow @nogc;
}

Result!Buffer jsonSchema(T)(ref scope RequestArena arena) nothrow @nogc;
Result!Buffer dispatchTool(T)(ref T tools, scope const(char)[] name, scope const(ubyte)[] jsonArguments,
        ref scope RequestArena arena, ref Context context) nothrow @nogc;
