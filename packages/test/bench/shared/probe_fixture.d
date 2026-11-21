module probe_fixture;

import core.runtime : Runtime, UnitTestResult;
import std.conv : to;

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

private string methods(size_t count) @safe
{
    string output;
    foreach (index; 0 .. count)
        output ~= "int method" ~ to!string(index) ~ "() const @safe nothrow @nogc;";
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
