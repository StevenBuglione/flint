/// Test helpers shared by the ported Spring Boot tests: AssertJ's `isThrownBy(...).withMessageContaining(...)`.
module boot_tests.support;

@safe:

/// Run `dg`, require it to throw `E`, and require the message to contain `fragment`.
void assertThrows(E : Throwable = Exception)(scope void delegate() @safe dg, string fragment = null,
        string file = __FILE__, size_t line = __LINE__)
{
    import std.algorithm.searching : canFind;
    import core.exception : AssertError;

    try
    {
        dg();
    }
    catch (E caught)
    {
        if (fragment.length && !caught.msg.canFind(fragment))
            throw new AssertError("expected a message containing '" ~ fragment ~ "', got '" ~ caught.msg.idup ~ "'",
                    file, line);
        return;
    }
    throw new AssertError("expected " ~ E.stringof ~ " to be thrown", file, line);
}

/// Registers every unittest of the module that mixes it in, so the runner can run them one by one and count them.
mixin template RegisterTests()
{
    shared static this()
    {
        import boot_tests.support : registerTest;

        static foreach (test; __traits(getUnitTests, mixin(__MODULE__)))
            registerTest(__MODULE__, __traits(getAttributes, test).length
                    ? __traits(getAttributes, test)[0] : "", &test);
    }
}

private struct Registered
{
    string module_;
    string name;
    void function() test;
}

private __gshared Registered[] registered;

/// Called by `RegisterTests`.
void registerTest(string module_, string name, void function() @safe test) @trusted nothrow
{
    // SAFETY: registration runs in module constructors, single-threaded, before the runner reads the list.
    registered ~= Registered(module_, name, test);
}

shared static this() @trusted
{
    // SAFETY: test-only runner setup, single-threaded at startup.
    import core.exception : AssertError, RangeError;
    import core.runtime : Runtime, UnitTestResult;

    Runtime.extendedModuleUnitTester = () {
        import std.file : chdir;
        import std.path : dirName;
        import std.stdio : stderr, writefln;

        // Resources are relative to the package (tests/resources/...): `dub test :boot-core` runs from the
        // repository root.
        chdir(__FILE_FULL_PATH__.dirName.dirName.dirName);

        UnitTestResult result;
        foreach (test; registered)
        {
            result.executed++;
            void report(Throwable failure)
            {
                stderr.writefln("FAIL %s: %s\n  %s:%s %s", test.module_, test.name, failure.file,
                        failure.line, failure.msg);
            }

            try
            {
                test.test();
                result.passed++;
            }
            catch (AssertError failure)
                report(failure);
            catch (RangeError failure)
                report(failure);
            catch (Exception failure)
                report(failure);
        }
        writefln("%s/%s ported Spring Boot tests passed", result.passed, result.executed);
        result.runMain = false;
        result.summarize = false;
        return result;
    };
}
