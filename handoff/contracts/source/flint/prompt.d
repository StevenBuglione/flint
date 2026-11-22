module flint.prompt;
import flint.arena : Result, Error;

@safe:
struct Choice
{
    string value;
    string label;
    bool disabled;
}

struct FormOptions
{
    bool requireTerminal = true;
    uint maxInputBytes = 4096;
}

Result!bool confirm(scope const(char)[] title, bool defaultValue = false);
Result!string input(scope const(char)[] title, scope const(char)[] defaultValue = "",
        FormOptions options = FormOptions.init);
Result!string select(scope const(char)[] title, scope const Choice[] choices);
Result!(string[]) multiSelect(scope const(char)[] title, scope const Choice[] choices, uint maxSelections = 64);
struct Secret
{
    @disable this(this);
    Error read(scope void delegate(scope const(ubyte)[]) @safe consumer) const;
    void clear();
}

Result!Secret password(scope const(char)[] title, FormOptions options = FormOptions.init);
struct Field
{
    string key;
    string title;
    bool required;
    bool secret;
}

struct Answer
{
    string key;
    string value;
    Secret secret;
    bool isSecret;
}

Result!(Answer[]) form(scope const Field[] fields, FormOptions options = FormOptions.init);
void clear(ref Answer[] answers);
