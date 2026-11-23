/++
Interim stand-in for third-party-apis' `flint.jackson.databind.ObjectMapper`: JSON *writing* of the values
Spring MVC's tests and gs-rest-service return, following Jackson 3.1.8's defaults as
docs/spring/phase1/third-party.md records them:
- a struct is a record: its properties print in declaration order (creator order);
- a class's properties print alphabetically (`SORT_PROPERTIES_ALPHABETICALLY`);
- strings escape `"`, `\` and control characters only (non-ASCII and `/` stay raw);
- doubles print as Java's `Double.toString`, and `NaN`/infinities as quoted strings;
- ordered maps (`LinkedHashMap!(string, Any)`) print in insertion order.
Deleted when the real databind lands; it is not a design for it.
+/
module flint.jackson.databind;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, DescriptorTable, TypeKind;
import flint.java.util : ArrayList, LinkedHashMap;

@safe:

/// A writer for one type that the mapper cannot describe on its own (Jackson's mixins and custom serializers).
alias CustomWriter = void delegate(ref Any value, JsonGenerator generator) @safe;

/// `JsonMappingException`-like failure to serialize.
class JsonMappingException : Exception
{
    ///
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc
    {
        super(message, file, line);
    }
}

/// The streaming writer (`tools.jackson.core.JsonGenerator`, reduced).
final class JsonGenerator
{
    private char[] buffer;
    private bool[] needsComma;
    private bool afterName;
    private ObjectMapper mapper;

    private this(ObjectMapper mapper) pure nothrow
    {
        this.mapper = mapper;
    }

    private void separate() pure nothrow
    {
        if (afterName)
        {
            afterName = false;
            return;
        }
        if (needsComma.length != 0)
        {
            if (needsComma[$ - 1])
                buffer ~= ',';
            needsComma[$ - 1] = true;
        }
    }

    /// `{`.
    void writeStartObject() pure nothrow
    {
        separate();
        buffer ~= '{';
        needsComma ~= false;
    }

    /// `}`.
    void writeEndObject() pure nothrow
    {
        buffer ~= '}';
        needsComma = needsComma[0 .. $ - 1];
    }

    /// `[`.
    void writeStartArray() pure nothrow
    {
        separate();
        buffer ~= '[';
        needsComma ~= false;
    }

    /// `]`.
    void writeEndArray() pure nothrow
    {
        buffer ~= ']';
        needsComma = needsComma[0 .. $ - 1];
    }

    /// A property name.
    void writeName(scope const(char)[] name) pure nothrow
    {
        separate();
        quote(name);
        buffer ~= ':';
        afterName = true;
    }

    /// A string value.
    void writeString(scope const(char)[] text) pure nothrow
    {
        separate();
        quote(text);
    }

    /// An integer value.
    void writeNumber(long value) pure nothrow
    {
        import std.conv : to;

        separate();
        buffer ~= value.to!string;
    }

    /// An unsigned integer value.
    void writeNumber(ulong value) pure nothrow
    {
        import std.conv : to;

        separate();
        buffer ~= value.to!string;
    }

    /// A double, as Java's `Double.toString`; `NaN` and the infinities are quoted.
    void writeNumber(double value) pure nothrow
    {
        separate();
        const nonFinite = value != value || value == double.infinity || value == -double.infinity;
        if (nonFinite)
        {
            buffer ~= value != value ? "\"NaN\"" : value > 0 ? "\"Infinity\"" : "\"-Infinity\"";
            return;
        }
        buffer ~= javaDouble(value);
    }

    /// `true` or `false`.
    void writeBoolean(bool value) pure nothrow
    {
        separate();
        buffer ~= value ? "true" : "false";
    }

    /// `null`.
    void writeNull() pure nothrow
    {
        separate();
        buffer ~= "null";
    }

    /// Any value, through the mapper.
    void writePOJO(Any value)
    {
        mapper.writeAny(value, this);
    }

    private void quote(scope const(char)[] text) pure nothrow
    {
        static immutable hex = "0123456789ABCDEF";
        buffer ~= '"';
        foreach (char c; text)
        {
            switch (c)
            {
            case '"':
                buffer ~= "\\\"";
                break;
            case '\\':
                buffer ~= "\\\\";
                break;
            case '\n':
                buffer ~= "\\n";
                break;
            case '\r':
                buffer ~= "\\r";
                break;
            case '\t':
                buffer ~= "\\t";
                break;
            case '\b':
                buffer ~= "\\b";
                break;
            case '\f':
                buffer ~= "\\f";
                break;
            default:
                if (c < 0x20)
                {
                    buffer ~= "\\u00";
                    buffer ~= hex[c >> 4];
                    buffer ~= hex[c & 15];
                }
                else
                    buffer ~= c;
            }
        }
        buffer ~= '"';
    }

    /// The text written so far.
    string text() const pure nothrow
    {
        return buffer.idup;
    }
}

// Interim: shortest round-trip digits in Java's plain layout for 1e-3 <= |v| < 1e7 (flint.serde.java_number
// is the real implementation; it is not reachable from this unregistered package).
private string javaDouble(double value) pure nothrow
{
    import std.format : format;
    import std.conv : to;

    if (value == cast(long) value && value < 1e7 && value > -1e7)
        return (cast(long) value).to!string ~ ".0";
    foreach (precision; 1 .. 18)
    {
        string text;
        try
            text = format("%.*f", precision, value);
        catch (Exception)
            return "0.0";
        double back;
        try
            back = text.to!double;
        catch (Exception)
            continue;
        if (back == value)
            return text;
    }
    try
        return format("%.17g", value);
    catch (Exception)
        return "0.0";
}

/// `ObjectMapper`, writing only.
class ObjectMapper
{
    private DescriptorTable descriptors;
    private CustomWriter[string] customWriters;

    /// A mapper over `descriptors` (a new table with the built-ins when `null`).
    this(DescriptorTable descriptors = null)
    {
        this.descriptors = descriptors is null ? DescriptorTable.withBuiltins() : descriptors;
    }

    /// Makes `descriptor` known.
    void registerDescriptor(Descriptor descriptor)
    {
        descriptors.add(descriptor);
    }

    /// The descriptor table.
    DescriptorTable getDescriptors() pure nothrow @nogc
    {
        return descriptors;
    }

    /// Whether values named `typeName` can be written.
    bool canSerialize(string typeName)
    {
        return (typeName in customWriters) !is null || descriptors.find(typeName) !is null || isBuiltin(typeName);
    }

    /// Writes values whose type, or a supertype, is named `typeName` with `writer`.
    void addCustomWriter(string typeName, CustomWriter writer)
    {
        customWriters[typeName] = writer;
    }

    /// `writeValueAsString`.
    string writeValueAsString(Any value)
    {
        auto generator = new JsonGenerator(this);
        writeAny(value, generator);
        return generator.text();
    }

    /// `writeValueAsBytes`: UTF-8.
    immutable(ubyte)[] writeValueAsBytes(Any value)
    {
        return cast(immutable(ubyte)[]) writeValueAsString(value);
    }

    private static bool isBuiltin(string name) pure nothrow @nogc
    {
        switch (name)
        {
        case "bool", "byte", "ubyte", "short", "ushort", "int", "uint", "long", "ulong", "float", "double", "string",
                "string[]", "int[]", "long[]":
            return true;
        default:
            return false;
        }
    }

    package void writeAny(Any value, JsonGenerator generator)
    {
        if (value.isNull())
        {
            generator.writeNull();
            return;
        }
        const name = value.typeName();
        if (auto custom = name in customWriters)
        {
            (*custom)(value, generator);
            return;
        }
        if (auto object = value.asObject())
        {
            foreach (base; supertypesOf(object))
                if (auto custom = base in customWriters)
                {
                    (*custom)(value, generator);
                    return;
                }
        }
        if (writeScalar(value, generator))
            return;
        if (value.holds!(LinkedHashMap!(string, Any)))
        {
            auto map = value.get!(LinkedHashMap!(string, Any));
            generator.writeStartObject();
            foreach (key, entry; map)
            {
                generator.writeName(key);
                writeAny(entry, generator);
            }
            generator.writeEndObject();
            return;
        }
        if (value.holds!(ArrayList!Any))
        {
            generator.writeStartArray();
            foreach (element; value.get!(ArrayList!Any))
                writeAny(element, generator);
            generator.writeEndArray();
            return;
        }
        if (value.holds!(string[]))
        {
            generator.writeStartArray();
            foreach (element; value.get!(string[]))
                generator.writeString(element);
            generator.writeEndArray();
            return;
        }
        auto descriptor = descriptors.find(name);
        if (descriptor is null)
            throw new JsonMappingException("No serializer found for class " ~ name);
        writeBean(value, descriptor, generator);
    }

    private static string[] supertypesOf(Object object) @trusted
    {
        // SAFETY (interim, not in source/): reads ClassInfo names only.
        string[] names;
        for (auto info = typeid(object); info !is null; info = info.base)
            names ~= info.name;
        foreach (i; typeid(object).interfaces)
            names ~= i.classinfo.name;
        return names;
    }

    private bool writeScalar(Any value, JsonGenerator generator)
    {
        static foreach (T; imported!"std.meta".AliasSeq!(byte, short, int, long))
            if (value.holds!T)
            {
                generator.writeNumber(cast(long) value.get!T);
                return true;
            }
        static foreach (T; imported!"std.meta".AliasSeq!(ubyte, ushort, uint, ulong))
            if (value.holds!T)
            {
                generator.writeNumber(cast(ulong) value.get!T);
                return true;
            }
        if (value.holds!double)
        {
            generator.writeNumber(value.get!double);
            return true;
        }
        if (value.holds!float)
        {
            generator.writeNumber(cast(double) value.get!float);
            return true;
        }
        if (value.holds!bool)
        {
            generator.writeBoolean(value.get!bool);
            return true;
        }
        if (value.holds!string)
        {
            generator.writeString(value.get!string);
            return true;
        }
        return false;
    }

    private void writeBean(Any value, Descriptor descriptor, JsonGenerator generator)
    {
        if (descriptor.kind == TypeKind.enum_)
        {
            generator.writeString(value.toString());
            return;
        }
        auto properties = descriptor.properties.dup;
        if (descriptor.kind == TypeKind.class_)
        {
            // Jackson 3: no creator, so properties sort by name (Java String order: UTF-16 units; ASCII here).
            for (size_t i = 1; i < properties.length; i++)
            {
                auto p = properties[i];
                size_t j = i;
                while (j > 0 && properties[j - 1].name > p.name)
                {
                    properties[j] = properties[j - 1];
                    j--;
                }
                properties[j] = p;
            }
        }
        generator.writeStartObject();
        foreach (ref property; properties)
        {
            if (property.get is null)
                continue;
            generator.writeName(property.name);
            writeAny(property.get(value), generator);
        }
        generator.writeEndObject();
    }
}
