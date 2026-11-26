/// Reporting code for the generated SpEL parity program.
module flint.spel_parity_compiled;

import flint.engine.aot.any : Any;
import flint.serde.java_number : javaDoubleString, javaFloatString;
import std.stdio : writeln;

@safe:

private void reportValue(Any value)
{
    const type = value.isNull() ? "null" : value.typeName();
    switch (type)
    {
    case "double":
        writeln(type, "\t", javaDoubleString(value.get!double));
        break;
    case "float":
        writeln(type, "\t", javaFloatString(value.get!float));
        break;
    default:
        writeln(type, "\t", value.toString());
        break;
    }
}
