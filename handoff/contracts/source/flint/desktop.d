// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.desktop;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
enum DesktopBackend : ubyte
{
    sdl,
    systemWebView
}

enum EventKind : ubyte
{
    close,
    resize,
    key,
    pointer,
    message
}

struct DesktopEvent
{
    EventKind kind;
    int x;
    int y;
    uint keyCode;
    Buffer message;
}

struct WindowOptions
{
    string title = "Flint";
    uint width = 1024;
    uint height = 768;
    DesktopBackend backend = DesktopBackend.sdl;
    bool resizable = true;
    string entryAsset = "index.html";
}

alias DesktopHandler = Error delegate(ref DesktopEvent event, ref scope RequestArena arena) @safe nothrow @nogc;
struct Window
{
    private ulong slot;
    private ulong generation;
    Error open(WindowOptions options);
    Error run(DesktopHandler handler, ref Context context) nothrow @nogc;
    Error submit(scope const(ubyte)[] commandBuffer) nothrow @nogc;
    Error close() nothrow @nogc;
}
