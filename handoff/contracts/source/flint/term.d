module flint.term;
import flint.arena : Error, Result;

@safe:
enum EventKind : ubyte
{
    key,
    resize,
    paste,
    mouse,
    eof,
    interrupt,
    timer,
    command
}

enum KeyCode : ushort
{
    unknown,
    character,
    enter,
    escape,
    tab,
    backspace,
    up,
    down,
    left,
    right,
    home,
    end,
    pageUp,
    pageDown,
    delete_,
    functionKey
}

struct KeyEvent
{
    KeyCode code;
    dchar character;
    bool control;
    bool alt;
    bool shift;
}

struct Size
{
    uint columns;
    uint rows;
}

struct MouseEvent
{
    uint column;
    uint row;
    ubyte button;
    bool pressed;
}

struct Event
{
    EventKind kind;
    KeyEvent key;
    Size size;
    MouseEvent mouse;
    string paste;
    ulong timerId;
    ulong commandId;
    ubyte[] payload;
    Error error;
}

enum ColorProfile : ubyte
{
    none,
    ansi16,
    ansi256,
    trueColor
}

struct Options
{
    bool raw = true;
    bool alternateScreen = true;
    bool mouse = false;
    bool bracketedPaste = true;
}

struct Session
{
    @disable this(this);
    static Result!Session open(Options options = Options.init);
    Result!Event next(long timeoutNanos);
    Error write(scope const(char)[] text);
    Result!Size size() const;
    ColorProfile colors() const;
    Error close();
}
