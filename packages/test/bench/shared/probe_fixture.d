module probe_fixture;

import core.runtime : Runtime, UnitTestResult;
import core.stdc.stdio : printf;

private uint checksum;

/// Record that one distinct compiled unit test ran.
void account(uint id) @safe nothrow @nogc
{
    checksum += id * (id + 1);
}

/// Sum of the observed unit test contributions.
uint suiteChecksum() @safe nothrow @nogc
{
    return checksum;
}

private UnitTestResult explicitTestRun()
{
    return UnitTestResult.pass;
}

shared static this()
{
    Runtime.extendedModuleUnitTester = &explicitTestRun;
}

/// Decimal text for compile-time generated declarations.
string decimal(ulong value) @safe pure nothrow
{
    char[20] digits;
    size_t start = digits.length;
    do
    {
        digits[--start] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    return digits[start .. $].idup;
}

/// Emit the consumed checksum in both binaries.
// SAFETY: The C format string is a fixed NUL-terminated literal with a matching scalar argument.
void printChecksum(uint checksum) @trusted nothrow @nogc
{
    printf("checksum=%u\n", checksum);
}

private string methods(size_t count) @safe
{
    string output;
    foreach (index; 0 .. count)
        output ~= "int method" ~ decimal(index) ~ "() const @safe nothrow @nogc;";
    return output;
}

/// Small mock workload.
interface One
{
    mixin(methods(1));
}

/// Mid-sized mock workload.
interface Sixteen
{
    mixin(methods(16));
}

/// Largest supported mock workload.
interface SixtyFour
{
    mixin(methods(64));
}

/// Sum from running 64 test blocks once each.
enum uint expectedSuite = 91_520;
/// Sum from dispatching every method in all three interfaces.
enum int expectedInterfaces = 2_217;
