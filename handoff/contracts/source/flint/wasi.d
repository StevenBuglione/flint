module flint.wasi;
import flint.arena : Error, Result;

@safe:
enum Engine : ubyte
{
    wasmtime,
    wamr
}

enum GuestAbi : ubyte
{
    core,
    wasiPreview1,
    wasi02Component,
    wasi03Component
}

struct Preopen
{
    string hostPath;
    string guestPath;
    bool writable;
}

struct Limits
{
    ulong fuel = 10000000;
    ulong maxMemoryBytes = 16777216;
    uint maxTableElements = 1024;
    uint maxInstances = 1;
    uint maxOutputBytes = 1048576;
    long wallTimeNanos = 1000000000;
}

struct PluginOptions
{
    Engine engine = Engine.wasmtime;
    GuestAbi abi = GuestAbi.core;
    Limits limits;
    Preopen[] preopens;
    bool inheritEnvironment = false;
    bool allowNetwork = false;
}

struct Plugin
{
    @disable this(this);
    static Result!Plugin load(scope const(ubyte)[] wasm, PluginOptions options = PluginOptions.init);
    Result!int callI32(scope const(char)[] exportName, scope const int[] args);
    Error interrupt();
    Error close();
}
