module assertion_errors_diagnostics_tests;

import flint.java.lang : AssertionError;
import flint.test.util : AssertionErrors;

@safe:

private void reports(scope void delegate() @safe check, string expected)
{
    try
    {
        check();
        assert(false);
    }
    catch (AssertionError failure)
        assert(failure.getMessage() == expected, failure.getMessage());
}

unittest
{
    reports(() { AssertionErrors.assertEquals("integer", long.min, ulong.max); },
            "integer expected:<-9223372036854775808> but was:<18446744073709551615>");
    reports(() { AssertionErrors.assertEquals("boolean", true, false); }, "boolean expected:<true> but was:<false>");
    reports(() { AssertionErrors.assertEquals("float", 1.2345678f, -0.0); }, "float expected:<1.23457> but was:<-0>");
    reports(() { AssertionErrors.assertNotEquals("integer", 257u, 257u); }, "integer was not expected to be:<257>");
}

unittest
{
    const(ubyte)[] expected = [0, 128, 255];
    const(ubyte)[] actual = [1, 128, 255];
    reports(() { AssertionErrors.assertEquals("unsigned", expected, actual); },
            "unsigned expected:<[0, 128, 255]> but was:<[1, 128, 255]>");

    byte[] signed = [-128, -1, 127];
    byte[] missing;
    reports(() { AssertionErrors.assertEquals("signed", signed, missing); },
            "signed expected:<[-128, -1, 127]> but was:<[]>");

    ubyte[3] fixed = [0, 128, 255];
    reports(() { AssertionErrors.assertEquals("fixed", fixed, actual); },
            "fixed expected:<[0, 128, 255]> but was:<[1, 128, 255]>");
}

private final class Sample
{
    override string toString() const
    {
        return "custom rendering";
    }
}

unittest
{
    reports(() { AssertionErrors.assertEquals("text", cast(string) null, "actual"); },
            "text expected:<null> but was:<actual>");
    reports(() { AssertionErrors.assertEquals("text", "", "actual"); }, "text expected:<> but was:<actual>");

    auto value = new Sample;
    reports(() { AssertionErrors.assertEquals("object", value, null); },
            "object expected:<" ~ typeid(value).name ~ "> but was:<null>");
}
