// Original Flint conformance test for the Java SE 21 System.lineSeparator contract.
module flint.java.system_line_separator_test;

import flint.java.lang : PublicSystem = System;
import flint.java.lang.system : System;

@safe:

@("System.lineSeparator returns the target platform's fixed separator")
unittest
{
    static assert(is(PublicSystem == System));
    version (Windows)
        enum expected = "\r\n";
    else
        enum expected = "\n";
    static assert(System.lineSeparator() == expected);
    assert(System.lineSeparator() == expected);
}
