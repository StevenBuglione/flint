module flint.tui;
public import flint.term : Event, EventKind, KeyCode, Size;
import flint.style : Style;
import flint.arena : Error, Result;

@safe:
struct Cell
{
    dchar rune = ' ';
    uint foreground;
    uint background;
    ushort attributes;
}

struct Frame
{
    uint columns;
    uint rows;
    Error put(uint column, uint row, scope const(char)[] text, Style style = Style.init);
    Error clear(Style style = Style.init);
}

struct CommandId
{
    ulong value;
}

struct TimerId
{
    ulong value;
}

alias Command = Event delegate() @safe;
struct Effects
{
    Result!CommandId submit(Command command);
    Error cancel(CommandId id);
    void quit(int exitCode = 0);
    Result!TimerId tick(long intervalNanos);
    Error cancelTimer(TimerId id);
}

struct RuntimeOptions
{
    uint maxFramesPerSecond = 60;
    uint maxPendingCommands = 256;
    uint maxEventsPerFrame = 1024;
}

int run(M)(ref M model, RuntimeOptions options = RuntimeOptions.init);
