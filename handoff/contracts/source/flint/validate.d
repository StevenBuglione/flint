/// Public API contract; declarations are not runtime implementations.
module flint.validate;
import flint.arena : Error, Text, RequestArena;

@safe:
struct Valid
{
}

struct NotBlank
{
}

struct Min
{
    long value;
}

struct Max
{
    long value;
}

struct Email
{
}

struct Pattern
{
    string value;
}

struct Size
{
    size_t min;
    size_t max;
}

struct Violation
{
    string field;
    string constraint;
    string message;
    uint[8] indexes;
    ubyte indexCount;
}

struct ValidationReport
{
    size_t written;
    size_t total;
    bool valid;
}

ValidationReport validate(T)(scope const ref T value, scope Violation[] output) nothrow @nogc;
ValidationReport validateIn(T)(scope const ref T value, ref scope RequestArena arena, scope Violation[] output) nothrow @nogc;
