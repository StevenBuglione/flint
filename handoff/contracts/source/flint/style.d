module flint.style;
@safe:
struct Color
{
    ubyte red;
    ubyte green;
    ubyte blue;
}

enum Alignment : ubyte
{
    start,
    center,
    end
}

enum Border : ubyte
{
    none,
    plain,
    rounded,
    double_
}

struct Insets
{
    uint top;
    uint right;
    uint bottom;
    uint left;
}

struct Style
{
    Color foreground;
    Color background;
    Insets padding;
    Insets margin;
    Border border;
    Alignment horizontal;
    Alignment vertical;
    bool bold;
    bool italic;
    bool underline;
}

struct TextMetrics
{
    uint cells;
    uint lines;
}

TextMetrics measure(scope const(char)[] utf8);
string render(scope const(char)[] utf8, Style style, uint width);
string joinHorizontal(scope const(char[])[] blocks, uint gap);
string joinVertical(scope const(char[])[] blocks, uint gap);
string truncateCells(scope const(char)[] utf8, uint maxCells, scope const(char)[] ellipsis = "…");
