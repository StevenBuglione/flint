/++
Flint tests for `flint.core.FlintVersion`, the port of `org.springframework.core.SpringVersion`. Spring has no test for
it, since its value comes from the JAR manifest.
+/
module flint.core.version_test;

import flint.core : FlintVersion;

@safe:

@("FlintVersion reports the Spring Framework release this module ports")
unittest
{
    static assert(is(typeof(FlintVersion.getVersion()) == string));
    assert(FlintVersion.getVersion() == "7.1.0");
}
