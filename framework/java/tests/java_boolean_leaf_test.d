module flint.java.boolean_leaf_test;

import flint.java.lang : LegacyBoolean = Boolean;
import flint.java.lang.boolean : Boolean;

@safe:

unittest
{
    static assert(is(LegacyBoolean == Boolean));
    const string[] truthy = ["true", "TRUE", "TrUe"];
    foreach (input; truthy)
        assert(Boolean.parseBoolean(input));
    const string[] falsy = [null, "", "yes", "false", "true ", "tru", "trué"];
    foreach (input; falsy)
        assert(!Boolean.parseBoolean(input));
    assert(Boolean.toString(true) == "true");
    assert(Boolean.toString(false) == "false");
    assert(Boolean.hashCode(true) == 1231);
    assert(Boolean.hashCode(false) == 1237);
}
