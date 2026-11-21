module flint.term.events;
import flint.arena : Error;

@safe:
/// Event presented to terminal consumers.
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

/// Normalized key identity.
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

/// One decoded key and its modifiers.
struct KeyEvent
{
    /// Key identity.
    KeyCode code;
    /// Unicode scalar, or the ordinal for a function key.
    dchar character;
    /// Control modifier.
    bool control;
    /// Alt modifier.
    bool alt;
    /// Shift modifier.
    bool shift;
}

/// Window dimensions in character cells.
struct Size
{
    /// Number of columns.
    uint columns;
    /// Number of rows.
    uint rows;
}

/// A normalized SGR mouse event.
struct MouseEvent
{
    /// One-based screen column.
    uint column;
    /// One-based screen row.
    uint row;
    /// Button ordinal, including wheel and extended buttons.
    ubyte button;
    /// True for a press.
    bool pressed;
}

/// Terminal input, size changes, or an application-injected event.
struct Event
{
    /// Active event category.
    EventKind kind;
    /// Decoded key when kind is key.
    KeyEvent key;
    /// New dimensions for a resize.
    Size size;
    /// Pointer details for a mouse event.
    MouseEvent mouse;
    /// Owned byte-preserving paste data.
    string paste;
    /// Identifier for an application timer.
    ulong timerId;
    /// Identifier for an application command.
    ulong commandId;
    /// Application-owned command payload.
    ubyte[] payload;
    /// Diagnostic for a recoverable input problem.
    Error error;
}

/// Color capability of the output stream.
enum ColorProfile : ubyte
{
    none,
    ansi16,
    ansi256,
    trueColor
}

/// Terminal modes applied while a session owns its terminal.
struct Options
{
    /// Disable canonical processing and terminal echo.
    bool raw = true;
    /// Enter the alternate screen when available.
    bool alternateScreen = true;
    /// Enable SGR mouse reporting.
    bool mouse = false;
    /// Ask the terminal to delimit pasted input.
    bool bracketedPaste = true;
}
