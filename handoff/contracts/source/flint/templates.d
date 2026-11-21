// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.templates;
import flint.arena : Buffer, Error, RequestArena, Result;

@safe:
struct HtmlTemplate
{
    string fileName;
}

struct TrustedHtml
{
    private Buffer content;
}

Result!Buffer render(string fileName, Model)(scope const ref Model model, ref scope RequestArena arena) nothrow @nogc;
Result!Buffer escapeHtml(scope const(ubyte)[] text, ref scope RequestArena arena) nothrow @nogc;
Error validateUrl(scope const(char)[] url) nothrow @nogc;
