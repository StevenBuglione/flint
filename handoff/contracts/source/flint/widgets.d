module flint.widgets;
import flint.tui : Frame, Effects, Event;
import flint.arena : Error;

@safe:
struct TextInput
{
    string value;
    string placeholder;
    bool password;
    uint maxBytes = 4096;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width) const;
}

struct TextArea
{
    string value;
    uint maxBytes = 1048576;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width, uint height) const;
}

struct ListItem
{
    ulong id;
    string label;
    bool disabled;
}

struct List
{
    ListItem[] items;
    size_t selected;
    string filter;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width, uint height) const;
}

struct Column
{
    string title;
    uint width;
}

struct Table
{
    Column[] columns;
    string[][] rows;
    size_t selected;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width, uint height) const;
}

struct Viewport
{
    string text;
    size_t firstLine;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width, uint height) const;
}

struct Progress
{
    double fraction;
    Error view(ref Frame frame, uint column, uint row, uint width) const;
}

struct Spinner
{
    uint frame;
    void tick();
    Error view(ref Frame frame, uint column, uint row) const;
}

struct Paginator
{
    size_t page;
    size_t pageCount;
    Error view(ref Frame frame, uint column, uint row) const;
}
