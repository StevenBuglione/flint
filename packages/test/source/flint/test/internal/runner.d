module flint.test.internal.runner;

@safe:

version (unittest)
{
    import flint.test : AssertionFailure;
    import std.algorithm.searching : canFind;
    import std.algorithm.sorting : sort;
    import std.array : Appender, appender;
    import std.format : format;
    import std.random : rndGen;
    import std.stdio : File, writeln;
    import std.utf : UseReplacementDchar, decode;

    package(flint.test) struct TestCase
    {
        string moduleName;
        string name;
        size_t ordinal;
        void function() @safe run;
    }

    package(flint.test) TestCase[] collect(Modules...)()
    {
        TestCase[] tests;
        string[] modules;
        static foreach (source; Modules)
        {
            {
                enum moduleName = __traits(fullyQualifiedName, source);
                // Deduplicate repeated modules in the explicit list.
                if (!modules.canFind(moduleName))
                {
                    modules ~= moduleName;
                    static foreach (index, test; __traits(getUnitTests, source))
                    {
                        {
                            enum fallback = format!"test-%s"(index + 1);
                            string name = fallback;
                            static foreach (attribute; __traits(getAttributes, test))
                            {
                                {
                                    static if (is(typeof(attribute) == string))
                                    {
                                        if (name == fallback && attribute.length != 0)
                                            name = attribute;
                                    }
                                }
                            }
                            static assert(is(typeof(&test) : void function() @safe), "Expected an @safe test");
                            tests ~= TestCase(moduleName, name, index, &test);
                        }
                    }
                }
            }
        }
        sort!((a, b) => a.moduleName == b.moduleName ? a.ordinal < b.ordinal : a.moduleName < b.moduleName)(tests);
        return tests;
    }

    private void xmlEscape(ref Appender!string output, scope const(char)[] source)
    {
        size_t offset;
        while (offset < source.length)
        {
            const start = offset;
            const scalar = decode!(UseReplacementDchar.yes)(source, offset);
            switch (scalar)
            {
            case '&':
                output.put("&amp;");
                break;
            case '<':
                output.put("&lt;");
                break;
            case '>':
                output.put("&gt;");
                break;
            case '"':
                output.put("&quot;");
                break;
            case '\'':
                output.put("&apos;");
                break;
            case '\t':
                output.put("&#9;");
                break;
            case '\n':
                output.put("&#10;");
                break;
            case '\r':
                output.put("&#13;");
                break;
            default:
                if (scalar < 32 || scalar == 0xfffe || scalar == 0xffff || scalar == 0xfffd)
                    output.put("\uFFFD");
                else
                    output.put(source[start .. offset]);
            }
        }
    }

    private void recordCase(ref Appender!string xml, TestCase test, string tag, string detail)
    {
        xml.put("  <testcase classname=\"");
        xmlEscape(xml, test.moduleName);
        xml.put("\" name=\"");
        xmlEscape(xml, test.name);
        if (tag.length == 0)
        {
            xml.put("\"/>\n");
            return;
        }
        xml.put("\"><" ~ tag ~ ">");
        xmlEscape(xml, detail);
        xml.put("</" ~ tag ~ "></testcase>\n");
    }

    // Write with exclusive creation so overlapping shards cannot overwrite an earlier receipt.
    private void writeReport(string path, uint seed, size_t total, size_t failed, size_t errors, string cases)
    {
        auto output = File(path, "wbx");
        output.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        output.writef!(`%s%s%s%s%s%s%s`)(`<testsuite name="Flint" tests="`, total, `" failures="`,
                failed, `" errors="`, errors, "\">\n");
        output.writef!("  <properties><property name=\"seed\" value=\"%s\"/></properties>\n")(seed);
        output.write(cases, "</testsuite>\n");
        output.close();
    }

    private string diagnostic(Throwable failure, uint seed)
    {
        return format!"%s:%s: %s (seed %s)"(failure.file, failure.line, failure.msg, seed);
    }

    package(flint.test) int execute(TestCase[] tests, string filter, bool failFast, string junitPath,
            uint seed, bool allowEmpty)
    {
        auto cases = appender!string;
        const saved = rndGen;
        scope (exit)
            rndGen = saved;
        rndGen.seed(seed);

        size_t total;
        size_t failed;
        size_t errors;
        foreach (test; tests)
        {
            const qualified = test.moduleName ~ "." ~ test.name;
            if (!qualified.canFind(filter))
                continue;
            ++total;
            string tag;
            string detail;
            try
                test.run();
            catch (AssertionFailure failure)
            {
                ++failed;
                tag = "failure";
                detail = diagnostic(failure, seed);
            }
            catch (Exception failure)
            {
                ++errors;
                tag = "error";
                detail = diagnostic(failure, seed);
            }
            if (tag.length != 0)
                writeln(qualified, ": ", tag, ": ", detail);
            else
                writeln(qualified, ": pass");
            if (junitPath.length != 0)
                recordCase(cases, test, tag, detail);
            if (failFast && tag.length != 0)
                break;
        }

        writeln("tests=", total, " failures=", failed, " errors=", errors, " seed=", seed);
        if (junitPath.length != 0)
        {
            try
                writeReport(junitPath, seed, total, failed, errors, cases.data);
            catch (Exception failure)
            {
                writeln("cannot write JUnit report: ", diagnostic(failure, seed));
                return 3;
            }
        }
        if (total == 0 && !allowEmpty)
            return 2;
        return failed + errors == 0 ? 0 : 1;
    }
}
