/++
Interim conformance copy of spring-core's `flint.core.NestedRuntimeException` (framework-core owns it;
deleted when `flint:core` lands).
+/
module flint.core;

import flint.java.lang : RuntimeException;

@safe:

/// `org.springframework.core.NestedRuntimeException`.
abstract class NestedRuntimeException : RuntimeException
{
    ///
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc
    {
        super(message, cause, file, line);
    }

    /// The innermost cause, or `null` when there is none.
    final Throwable getRootCause() pure nothrow @nogc
    {
        Throwable rootCause = null;
        Throwable cause = next;
        while (cause !is null && cause !is rootCause)
        {
            rootCause = cause;
            cause = cause.next;
        }
        return rootCause;
    }

    /// The root cause, or this exception.
    final Throwable getMostSpecificCause() pure nothrow @nogc
    {
        auto rootCause = getRootCause();
        return rootCause !is null ? rootCause : this;
    }
}

/++
`org.springframework.core.MethodParameter`, reduced to a handler parameter described by Flint AOT's
`ArgumentSpec` (contract 1 section 4.5): its index, name, declared type name and merged annotations.
Replaced by framework-core's `flint.core.MethodParameter`.
+/
final class MethodParameter
{
    import flint.engine.aot.descriptor : MergedAnnotation, findAnnotation;
    import flint.engine.aot.mapping : ArgumentSpec;

    private ArgumentSpec argument;
    private int index;
    private string owner;

    ///
    this(ArgumentSpec argument, int index, string owner = null) pure nothrow
    {
        this.argument = argument;
        this.index = index;
        this.owner = owner;
    }

    /// The parameter's position; `-1` for a return type.
    int getParameterIndex() const pure nothrow @nogc
    {
        return index;
    }

    /// The parameter name.
    string getParameterName() const pure nothrow @nogc
    {
        return argument.name;
    }

    /// The fully qualified declared type (Java's `getParameterType()`, a `Class`; R4).
    string getParameterType() const pure nothrow @nogc
    {
        return argument.type;
    }

    /// The type after unwrapping `Optional!T` (Java's `getNestedParameterType()`).
    string getNestedParameterType() const pure nothrow
    {
        enum prefix = "flint.java.util.Optional!(";
        const type = argument.type;
        if (type.length > prefix.length + 1 && type[0 .. prefix.length] == prefix && type[$ - 1] == ')')
            return type[prefix.length .. $ - 1];
        return type;
    }

    /// Whether the parameter is `Optional!T` (or a `Nullable!T`).
    bool isOptional() const pure nothrow
    {
        return getNestedParameterType() != argument.type;
    }

    /// The merged annotation of `type` (fully qualified), or `null`.
    const(MergedAnnotation)* getParameterAnnotation(string type) const nothrow @nogc
    {
        return findAnnotation(argument.annotations, type);
    }

    /// The annotation of type `A`, or `A.init` with `found` false.
    A getParameterAnnotation(A)(out bool found) const
    {
        import flint.engine.aot.name : typeNameOf;

        auto merged = getParameterAnnotation(typeNameOf!A);
        found = merged !is null;
        if (!found)
            return A.init;
        A value = merged.value.get!A();
        return value;
    }

    /// Whether the annotation of type `A` is present.
    bool hasParameterAnnotation(A)() const
    {
        import flint.engine.aot.name : typeNameOf;

        return getParameterAnnotation(typeNameOf!A) !is null;
    }

    /// The AOT argument record.
    ref const(ArgumentSpec) getArgumentSpec() const return pure nothrow @nogc
    {
        return argument;
    }

    /// The declaring method's description, for messages (`OwnerController.getOwner`).
    string getExecutable() const pure nothrow @nogc
    {
        return owner;
    }

    override string toString() const
    {
        import std.conv : to;

        return "method '" ~ owner ~ "' parameter " ~ index.to!string;
    }
}

/// Interim stand-in for spring-core's `ConversionService`, for the string-to-type conversion of request
/// values: scalars, `string`, `bool`, and arrays of them by comma splitting. Throws `ConversionFailedException`.
struct SimpleConversion
{
    import flint.engine.aot.any : Any;

    /// Whether `targetType` is one this converter handles.
    static bool canConvert(string targetType) pure nothrow @nogc
    {
        switch (targetType)
        {
        case "string", "bool", "byte", "ubyte", "short", "ushort", "int", "uint", "long", "ulong",
                "float", "double", "char", "string[]", "int[]", "long[]":
                return true;
        default:
            return false;
        }
    }

    /// `value` converted to `targetType`.
    static Any convert(string value, string targetType)
    {
        import std.conv : ConvException, to;
        import std.string : strip;

        try
        {
            switch (targetType)
            {
            case "string":
                return Any.of(value);
            case "bool":
                return Any.of(parseBoolean(value));
            case "byte":
                return Any.of(value.strip.to!byte);
            case "ubyte":
                return Any.of(value.strip.to!ubyte);
            case "short":
                return Any.of(value.strip.to!short);
            case "ushort":
                return Any.of(value.strip.to!ushort);
            case "int":
                return Any.of(value.strip.to!int);
            case "uint":
                return Any.of(value.strip.to!uint);
            case "long":
                return Any.of(value.strip.to!long);
            case "ulong":
                return Any.of(value.strip.to!ulong);
            case "float":
                return Any.of(value.strip.to!float);
            case "double":
                return Any.of(value.strip.to!double);
            case "char":
                if (value.length != 1)
                    throw new ConvException("not a single character");
                return Any.of(value[0]);
            case "string[]":
                return Any.of(splitComma(value));
            case "int[]":
                {
                    int[] result;
                    foreach (part; splitComma(value))
                        result ~= part.strip.to!int;
                    return Any.of(result);
                }
            case "long[]":
                {
                    long[] result;
                    foreach (part; splitComma(value))
                        result ~= part.strip.to!long;
                    return Any.of(result);
                }
            default:
                throw new ConversionFailedException("String", targetType, value, null);
            }
        }
        catch (ConvException e)
            throw new ConversionFailedException("String", targetType, value,
                    new imported!"flint.java.lang".NumberFormatException(forInput(value)));
    }

    private static string forInput(string value) pure nothrow
    {
        return "For input string: \"" ~ value ~ "\"";
    }

    private static bool parseBoolean(string value)
    {
        import std.conv : ConvException;
        import std.uni : toLower;

        switch (value.toLower)
        {
        case "true", "on", "yes", "1":
            return true;
        case "false", "off", "no", "0":
            return false;
        default:
            throw new ConvException("Invalid boolean value '" ~ value ~ "'");
        }
    }

    private static string[] splitComma(string value) pure nothrow
    {
        string[] result;
        size_t start;
        foreach (i, c; value)
            if (c == ',')
            {
                result ~= value[start .. i];
                start = i + 1;
            }
        result ~= value[start .. $];
        return result;
    }
}

/// `org.springframework.core.convert.ConversionFailedException`, reduced to type names (R4).
class ConversionFailedException : NestedRuntimeException
{
    private string sourceType;
    private string targetType;
    private string value;

    ///
    this(string sourceType, string targetType, string value, Throwable cause, string file = __FILE__,
            size_t line = __LINE__) pure nothrow
    {
        super("Failed to convert from type [java.lang." ~ sourceType ~ "] to type [" ~ javaTypeName(
                targetType) ~ "] for value [" ~ value ~ "]", cause, file, line);
        this.sourceType = sourceType;
        this.targetType = targetType;
        this.value = value;
    }

    /// The target type name.
    string getTargetType() const pure nothrow @nogc
    {
        return targetType;
    }

    /// The value that failed.
    string getValue() const pure nothrow @nogc
    {
        return value;
    }
}

/// Java's name for a D scalar type, as Spring's messages print it (`long` → `long`, `string` → `java.lang.String`).
string javaTypeName(string type) pure nothrow
{
    switch (type)
    {
    case "string":
        return "java.lang.String";
    case "bool":
        return "boolean";
    case "ubyte":
        return "byte";
    case "ushort":
        return "short";
    case "uint":
        return "int";
    case "ulong":
        return "long";
    case "string[]":
        return "java.lang.String[]";
    default:
        return type;
    }
}
