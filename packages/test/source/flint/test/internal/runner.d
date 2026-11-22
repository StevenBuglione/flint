module flint.test.internal.runner;

@safe:

version (unittest)
{
    import flint.test : AssertionFailure;
    import flint.test.internal.mocks : decimal;

    package(flint.test) struct TestCase
    {
        string moduleName;
        string name;
        size_t ordinal;
        void function() @safe run;
    }

    // One test in the compile-time plan; `slot` indexes the declaration-order address table in `collect`.
    private struct Planned
    {
        string moduleName;
        string name;
        size_t ordinal;
        size_t slot;
    }

    package(flint.test) TestCase[] collect(Modules...)()
    {
        // Names, deduplication and ordering are resolved at compile time. The executable stores one function
        // address per test and copies a constant table instead of unrolled registration and sorting code.
        static immutable Planned[] plan = planOf!Modules();
        enum slots = () {
            size_t count;
            static foreach (source; Modules)
                count += __traits(getUnitTests, source).length;
            return count;
        }();
        void function() @safe[slots] runs;
        size_t slot;
        static foreach (source; Modules)
        {
            static foreach (test; __traits(getUnitTests, source))
            {
                static assert(is(typeof(&test) : void function() @safe), "Expected an @safe test");
                runs[slot++] = &test;
            }
        }
        auto tests = new TestCase[plan.length];
        foreach (index, ref entry; plan)
            tests[index] = TestCase(entry.moduleName, entry.name, entry.ordinal, runs[entry.slot]);
        return tests;
    }

    private Planned[] planOf(Modules...)()
    {
        // Every compiled test is recorded with the position of its module in the explicit list; repeated modules
        // are dropped and the rest sorted by `ordered`, so nothing below is instantiated per module or test.
        enum slots = () {
            size_t count;
            static foreach (source; Modules)
                count += __traits(getUnitTests, source).length;
            return count;
        }();
        auto tests = new Planned[slots];
        auto positions = new size_t[slots];
        string[Modules.length] modules;
        size_t slot;
        static foreach (position, source; Modules)
        {
            modules[position] = __traits(fullyQualifiedName, source);
            static foreach (index, test; __traits(getUnitTests, source))
            {
                {
                    const fallback = fallbackName(index);
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
                    tests[slot] = Planned(modules[position], name, index, slot);
                    positions[slot] = position;
                    ++slot;
                }
            }
        }
        return ordered(tests, positions, modules[]);
    }

    private string fallbackName(size_t index) pure nothrow
    {
        return "test-" ~ decimal(index + 1);
    }

    // Keep the tests of each module's first occurrence in the explicit list, then sort them.
    private Planned[] ordered(scope const Planned[] all, scope const size_t[] owners, scope const string[] modules) pure
    {
        Planned[] tests;
        foreach (index, entry; all)
        {
            bool first = true;
            foreach (prior; 0 .. owners[index])
            {
                if (modules[prior] == modules[owners[index]])
                    first = false;
            }
            if (first)
                tests ~= entry;
        }
        // Insertion sort by module, then declaration order; the keys are unique after deduplication.
        foreach (position; 1 .. tests.length)
        {
            const entry = tests[position];
            size_t at = position;
            for (; at > 0 && precedes(entry, tests[at - 1]); --at)
                tests[at] = tests[at - 1];
            tests[at] = entry;
        }
        return tests;
    }

    private bool precedes(scope const Planned a, scope const Planned b) pure nothrow @nogc
    {
        return a.moduleName == b.moduleName ? a.ordinal < b.ordinal : a.moduleName < b.moduleName;
    }

    /// `std.utf.decode!(UseReplacementDchar.yes)` over UTF-8: the same scalar, and the same number of code
    /// units consumed, for every valid and invalid sequence.
    package(flint.test) dchar decodeReplacing(scope const(char)[] source, ref size_t index) pure nothrow @nogc
    {
        enum dchar replacement = 0xFFFD;
        static immutable uint[4] mask = [(1 << 7) - 1, (1 << 11) - 1, (1 << 16) - 1, (1 << 21) - 1];
        const ubyte lead = source[index];
        if (lead < 0x80)
        {
            ++index;
            return lead;
        }
        if ((lead & 0b1100_0000) != 0b1100_0000)
        {
            ++index;
            return replacement;
        }
        const length = source.length - index;
        uint scalar = lead;
        ubyte control = lead;
        control <<= 1;
        foreach (i; 1 .. 4)
        {
            if (i == length)
            {
                index += i;
                return replacement;
            }
            const ubyte next = source[index + i];
            if ((next & 0xC0) != 0x80)
            {
                index += i + 1;
                return replacement;
            }
            scalar = (scalar << 6) | (next & 0x3F);
            control <<= 1;
            if (!(control & 0x80))
            {
                scalar &= mask[i];
                // Overlong (fits in fewer units), surrogate (three units) or beyond U+10FFFF (four units).
                const invalid = (scalar & ~mask[i - 1]) == 0 || (i == 2 && !(scalar < 0xD800
                        || (scalar > 0xDFFF && scalar <= 0x10FFFF))) || (i == 3 && scalar > dchar.max);
                index += i + 1;
                const dchar decoded = scalar;
                return invalid ? replacement : decoded;
            }
        }
        index += 4;
        return replacement;
    }

    // Byte-wise substring test, as `std.algorithm.searching.canFind` on two UTF-8 strings.
    private bool contains(scope const(char)[] text, scope const(char)[] part) pure nothrow @nogc
    {
        if (part.length > text.length)
            return false;
        foreach (start; 0 .. text.length - part.length + 1)
        {
            if (text[start .. start + part.length] == part)
                return true;
        }
        return false;
    }

    private void xmlEscape(ref string output, scope const(char)[] source)
    {
        size_t offset;
        while (offset < source.length)
        {
            const start = offset;
            const scalar = decodeReplacing(source, offset);
            switch (scalar)
            {
            case '&':
                output ~= "&amp;";
                break;
            case '<':
                output ~= "&lt;";
                break;
            case '>':
                output ~= "&gt;";
                break;
            case '"':
                output ~= "&quot;";
                break;
            case '\'':
                output ~= "&apos;";
                break;
            case '\t':
                output ~= "&#9;";
                break;
            case '\n':
                output ~= "&#10;";
                break;
            case '\r':
                output ~= "&#13;";
                break;
            default:
                if (scalar < 32 || scalar == 0xfffe || scalar == 0xffff || scalar == 0xfffd)
                    output ~= "\uFFFD";
                else
                    output ~= source[start .. offset];
            }
        }
    }

    private void recordCase(ref string xml, TestCase test, string tag, string detail)
    {
        xml ~= "  <testcase classname=\"";
        xmlEscape(xml, test.moduleName);
        xml ~= "\" name=\"";
        xmlEscape(xml, test.name);
        if (tag.length == 0)
        {
            xml ~= "\"/>\n";
            return;
        }
        xml ~= "\"><" ~ tag ~ ">";
        xmlEscape(xml, detail);
        xml ~= "</" ~ tag ~ "></testcase>\n";
    }

    // Write with exclusive creation so overlapping shards cannot overwrite an earlier receipt.
    private void writeReport(string path, uint seed, size_t total, size_t failed, size_t errors, string cases)
    {
        import flint.test.sys : createExclusive, errorText;

        const document = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuite name=\"Flint\" tests=\"" ~ decimal(
                total) ~ "\" failures=\"" ~ decimal(failed) ~ "\" errors=\"" ~ decimal(
                errors) ~ "\">\n  <properties><property name=\"seed\" value=\"" ~ decimal(
                seed) ~ "\"/></properties>\n" ~ cases ~ "</testsuite>\n";
        const code = createExclusive(path, document);
        if (code != 0)
            throw new Exception("Cannot write `" ~ path ~ "' exclusively (" ~ errorText(code) ~ ")");
    }

    private string diagnostic(Throwable failure, uint seed)
    {
        return failure.file ~ ":" ~ decimal(failure.line) ~ ": " ~ failure.msg ~ " (seed " ~ decimal(seed) ~ ")";
    }

    // One line on standard output through a single writer instance.
    private void printLine(scope const(char)[] line)
    {
        import flint.test.sys : writeLine;

        writeLine(line);
    }

    package(flint.test) int execute(TestCase[] tests, string filter, bool failFast, string junitPath,
            uint seed, bool allowEmpty)
    {
        import core.memory : pureFree;
        import std.random : rndGen;

        // std.random's archive member references the druntime template instance `pureFree!()`, which the
        // release Phobos archive only defines inside unrelated members. Without a definition already in the
        // link, the static linker satisfies it with std.variant's member and, through that member's own
        // references, std.net.curl, std.concurrency, std.datetime and std.encoding: about 500 KB in every
        // test executable. Referencing the instance here emits it beside the runner, so seeding the
        // generator links std.random alone. The behaviour is unchanged; only the archive members differ.
        static immutable pureFreeInstance = &pureFree!();
        assert(pureFreeInstance !is null);

        string cases;
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
            if (!contains(qualified, filter))
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
                printLine(qualified ~ ": " ~ tag ~ ": " ~ detail);
            else
                printLine(qualified ~ ": pass");
            if (junitPath.length != 0)
                recordCase(cases, test, tag, detail);
            if (failFast && tag.length != 0)
                break;
        }

        printLine("tests=" ~ decimal(total) ~ " failures=" ~ decimal(failed) ~ " errors=" ~ decimal(
                errors) ~ " seed=" ~ decimal(seed));
        if (junitPath.length != 0)
        {
            try
                writeReport(junitPath, seed, total, failed, errors, cases);
            catch (Exception failure)
            {
                printLine("cannot write JUnit report: " ~ diagnostic(failure, seed));
                return 3;
            }
        }
        if (total == 0 && !allowEmpty)
            return 2;
        return failed + errors == 0 ? 0 : 1;
    }
}
