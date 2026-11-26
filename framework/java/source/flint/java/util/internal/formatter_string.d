/// String rendering for Java Formatter.
module flint.java.util.internal.formatter_string;

import flint.engine.aot.any : Any;
import flint.java.util.internal.formatter_support : FormatOptions, truncate;
import flint.java.util.internal.formatter_unicode : rootUppercase;

@safe:

/// Render a Java String.valueOf projection with UTF-16 precision and optional uppercase.
package(flint.java) string formatString(const ref FormatOptions spec, Any argument)
{
    const text = truncate(spec, stringText(argument));
    return spec.conversion == 'S' ? rootUppercase(text) : text;
}

/// `String.valueOf` of the argument.
private string stringText(Any argument)
{
    import flint.java.lang : doubleToString, floatToString;

    if (argument.isNull)
        return "null";
    switch (argument.typeName)
    {
    case "double":
        return doubleToString(argument.get!double);
    case "float":
        return floatToString(cast(float) argument.get!double);
    default:
        break;
    }
    if (auto object = argument.asObject())
    {
        import flint.engine.aot.objects : objectToString;

        return objectToString(object);
    }
    return argument.toString();
}
