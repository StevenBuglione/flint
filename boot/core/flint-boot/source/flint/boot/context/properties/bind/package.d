// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/context/properties/bind/Binder.java
// with Bindable.java, BindResult.java, BindException.java, BindHandler.java, DataObjectPropertyName.java,
// DefaultValue.java, JavaBeanBinder.java, ValueObjectBinder.java, PlaceholdersResolver.java and
// PropertySourcesPlaceholdersResolver.java from the same directory, and BindConverter.java with
// org/springframework/boot/convert/DurationStyle.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: binding runs on Flint AOT descriptors (`flint.engine.aot`) instead of reflection,
// through an erased engine with a one-line typed façade (ADR-030 section 5).

/// `org.springframework.boot.context.properties.bind`: binding configuration properties onto objects.
///
/// `Binder.bind!T("flint.datasource")` binds every property under the name onto a `T`. It follows Boot's rules:
/// - names are relaxed (`maxPoolSize`, `max-pool-size`, `MAX_POOL_SIZE`);
/// - `${...}` placeholders resolve against the same sources;
/// - JavaBean types get their properties set;
/// - value objects, whose preferred constructor takes parameters, are built through that constructor, with
///   `@DefaultValue` for absent parameters.
///
/// The engine is erased: `Binder.bind(name, descriptor, instance)` works from the type's `Descriptor`, which is
/// what generated `@ConfigurationProperties` code calls.
module flint.boot.context.properties.bind;

import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName,
    ConfigurationPropertySource, ConfigurationPropertySources;
import flint.java.lang : IllegalStateException, RuntimeException;
import flint.java.util : NoSuchElementException;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, DescriptorTable, TypeKind, descriptorOf;
import flint.engine.aot.name : typeNameOf;

@safe:

/// `@DefaultValue`: the value of a constructor parameter, or of a nested value object, when nothing is bound.
struct DefaultValue
{
    /// The default, as text converted like a property value; several values make a list.
    string[] value;
}

/// The result of a bind: a value, or nothing.
struct BindResult(T)
{
    private T value;
    private bool bound;

    /// A bound result.
    static BindResult of(T value)
    {
        return BindResult(value, true);
    }

    /// Whether a value was bound.
    bool isBound() const pure nothrow @nogc
    {
        return bound;
    }

    /// The bound value. Throws `NoSuchElementException` when nothing was bound.
    T get()
    {
        if (!bound)
            throw new NoSuchElementException("No value bound");
        return value;
    }

    /// The bound value, or `other`.
    T orElse(T other)
    {
        return bound ? value : other;
    }

    /// The bound value, or the result of `other`.
    T orElseGet(scope T delegate() @safe other)
    {
        return bound ? value : other();
    }

    /// Call `consumer` with the value when one was bound.
    void ifBound(scope void delegate(T) @safe consumer)
    {
        if (bound)
            consumer(value);
    }

    /// A result holding `mapper(value)`, or nothing.
    BindResult!U map(U)(scope U delegate(T) @safe mapper)
    {
        return bound ? BindResult!U.of(mapper(value)) : BindResult!U.init;
    }
}

/// What to bind: a type, and optionally an existing value to bind into.
struct Bindable(T)
{
    private T existing;
    private bool hasExisting;

    /// A bindable of `T`.
    static Bindable of()
    {
        return Bindable.init;
    }

    /// A bindable of `T` that binds into `instance`.
    static Bindable ofInstance(T instance)
    {
        return Bindable(instance, true);
    }

    /// A copy that binds into `instance`.
    Bindable withExistingValue(T instance)
    {
        return Bindable(instance, true);
    }

    /// The existing value, if any.
    bool hasExistingValue() const pure nothrow @nogc
    {
        return hasExisting;
    }

    /// The existing value; `T.init` when there is none.
    T getValue()
    {
        return existing;
    }
}

/// Thrown when binding fails: the name being bound, the target type and the property that broke.
class BindException : RuntimeException
{
    private ConfigurationPropertyName name;
    private string target;
    private ConfigurationProperty property;

    /// Binding `name` to `target` failed at `property` (may be `null`) because of `cause`.
    this(ConfigurationPropertyName name, string target, ConfigurationProperty property, Throwable cause)
    {
        super("Failed to bind properties under '" ~ name.toString() ~ "' to " ~ target, cause);
        this.name = name;
        this.target = target;
        this.property = property;
    }

    /// The name being bound.
    ConfigurationPropertyName getName() pure nothrow @nogc
    {
        return name;
    }

    /// The fully qualified name of the target type.
    string getTarget() const pure nothrow @nogc
    {
        return target;
    }

    /// The property whose value could not be bound, or `null`.
    ConfigurationProperty getProperty() pure nothrow @nogc
    {
        return property;
    }
}

/// Thrown by the converter when text is not a valid value of the target type.
class ConversionFailedException : RuntimeException
{
    private string targetType;
    private string reason;

    /// `value` could not become a `type`, because of `reason` (may be `null`).
    this(string value, string type, string reason = null) pure
    {
        super("Failed to convert from type [java.lang.String] to type [" ~ type ~ "] for value [" ~ value ~ "]" ~ (
                reason.length ? "; " ~ reason : ""));
        this.targetType = type;
        this.reason = reason;
    }

    /// The source type, as Spring names it.
    string getSourceType() const pure nothrow @nogc
    {
        return "java.lang.String";
    }

    /// The target type's fully qualified name.
    string getTargetType() const pure nothrow @nogc
    {
        return targetType;
    }

    /// Why the conversion failed, or `null`.
    string getReason() const pure nothrow @nogc
    {
        return reason;
    }
}

/// Resolves `${...}` placeholders in property values.
interface PlaceholdersResolver
{
    /// `value` with its placeholders resolved.
    string resolvePlaceholders(string value);
}

/// Resolves placeholders against configuration property sources, as Boot's `PropertySourcesPlaceholdersResolver`
/// does with spring-core's `PropertyPlaceholderHelper`: `${name}`, `${name:default}`, nesting, `\${` escapes, and
/// unresolvable placeholders left as written.
final class PropertySourcesPlaceholdersResolver : PlaceholdersResolver
{
    private ConfigurationPropertySource[] sources;

    /// A resolver over `sources`, highest precedence first.
    this(ConfigurationPropertySource[] sources) pure nothrow @nogc
    {
        this.sources = sources;
    }

    /// `value` with `${name}` and `${name:default}` resolved against the sources.
    string resolvePlaceholders(string value)
    {
        return resolve(value, null);
    }

    private string resolve(string value, string[] visiting)
    {
        import std.string : indexOf;

        if (value.indexOf("${") < 0)
            return unescape(value);
        string result;
        size_t index;
        while (index < value.length)
        {
            if (value[index] == '\\' && index + 2 < value.length && value[index + 1] == '$' && value[index + 2] == '{')
            {
                result ~= "${";
                index += 3;
                continue;
            }
            if (value[index] == '$' && index + 1 < value.length && value[index + 1] == '{')
            {
                const end = closing(value, index + 2);
                if (end < 0)
                {
                    result ~= value[index .. $];
                    break;
                }
                result ~= placeholder(value, index, end, visiting);
                index = end + 1;
                continue;
            }
            result ~= value[index++];
        }
        return result;
    }

    private string placeholder(string value, size_t start, long end, string[] visiting)
    {
        import std.string : indexOf;

        const content = resolve(value[start + 2 .. cast(size_t) end], visiting);
        const separator = defaultSeparator(content);
        const key = separator < 0 ? content : content[0 .. separator];
        foreach (seen; visiting)
        {
            if (seen == key)
                throw new IllegalStateException("Circular placeholder reference '" ~ key ~ "' in property definitions");
        }
        string found;
        if (ConfigurationPropertyName.isValid(key))
        {
            auto property = ConfigurationPropertySources.find(sources, ConfigurationPropertyName.of(key));
            if (property !is null)
                found = property.getValue();
        }
        if (found is null)
        {
            auto adapted = ConfigurationPropertyName.adapt(key, '.');
            if (!adapted.isEmpty())
            {
                auto property = ConfigurationPropertySources.find(sources, adapted);
                if (property !is null)
                    found = property.getValue();
            }
        }
        if (found !is null)
            return resolve(found, visiting ~ key);
        if (separator >= 0)
            return content[separator + 1 .. $];
        return value[start .. cast(size_t) end + 1];
    }

    private static long closing(string value, size_t from) pure nothrow @nogc
    {
        int depth = 1;
        for (size_t i = from; i < value.length; i++)
        {
            if (value[i] == '{' && i > 0 && value[i - 1] == '$')
                depth++;
            else if (value[i] == '}' && --depth == 0)
                return cast(long) i;
        }
        return -1;
    }

    // The `:` separating a default, outside nested placeholders.
    private static long defaultSeparator(string content) pure nothrow @nogc
    {
        int depth;
        foreach (i, char ch; content)
        {
            if (ch == '{')
                depth++;
            else if (ch == '}')
                depth--;
            else if (ch == ':' && depth == 0)
                return cast(long) i;
        }
        return -1;
    }

    private static string unescape(string value) pure
    {
        import std.array : replace;

        return value.replace("\\${", "${");
    }
}

/// `DataObjectPropertyName.toDashedForm`: a Java Beans property name in Boot's dashed form (`maxPoolSize` →
/// `max-pool-size`), leaving `[...]` indexes as written.
string toDashedForm(string name) pure
{
    import std.ascii : isUpper, toLower;

    char[] result;
    bool inIndex;
    foreach (char ch; name)
    {
        if (inIndex)
        {
            result ~= ch;
            inIndex = ch != ']';
            continue;
        }
        if (ch == '[')
        {
            inIndex = true;
            result ~= ch;
            continue;
        }
        const c = ch != '_' ? ch : '-';
        if (isUpper(c) && result.length && result[$ - 1] != '-')
            result ~= '-';
        result ~= toLower(c);
    }
    return result.idup;
}

/// Binds configuration properties onto objects described by Flint AOT descriptors.
final class Binder
{
    private ConfigurationPropertySource[] sources;
    private PlaceholdersResolver placeholders;
    private DescriptorTable descriptors;

    /// A binder over `sources` (highest precedence first). Placeholders resolve against the same sources unless
    /// `placeholders` is given; nested types are looked up in `descriptors`.
    this(ConfigurationPropertySource[] sources, PlaceholdersResolver placeholders = null,
            DescriptorTable descriptors = null)
    {
        this.sources = sources;
        this.placeholders = placeholders is null ? new PropertySourcesPlaceholdersResolver(sources) : placeholders;
        this.descriptors = descriptors is null ? DescriptorTable.withBuiltins() : descriptors;
    }

    /// The descriptor table nested types are found in; callers may add descriptors to it.
    DescriptorTable getDescriptors() pure nothrow @nogc
    {
        return descriptors;
    }

    /// Bind the properties under `name` onto a new `T`.
    BindResult!T bind(T)(string name)
    {
        return bind!T(name, Bindable!T.of());
    }

    /// Bind the properties under `name` onto `target`'s existing value, or onto a new `T`.
    BindResult!T bind(T)(string name, Bindable!T target)
    {
        auto descriptor = describe!T();
        Any instance = target.hasExistingValue() ? Any.of(target.getValue()) : Any.init;
        if (!bind(ConfigurationPropertyName.of(name), descriptor, instance))
            return BindResult!T.init;
        return BindResult!T.of(instance.get!T);
    }

    /// Bind the properties under `name`, or create a default `T` when none is bound.
    T bindOrCreate(T)(string name)
    {
        auto descriptor = describe!T();
        Any instance;
        if (!bind(ConfigurationPropertyName.of(name), descriptor, instance))
            instance = create(ConfigurationPropertyName.of(name), descriptor);
        return instance.get!T;
    }

    /// The erased engine: bind `name` onto a value of `type`, starting from `instance` when it holds one.
    /// Returns whether anything was bound; `instance` then holds the result. Throws `BindException`.
    bool bind(ConfigurationPropertyName name, const Descriptor type, ref Any instance)
    {
        try
            return bindValue(name, type, instance);
        catch (BindException failure)
            throw failure;
        catch (ConversionFailedException failure)
            throw new BindException(name, type.name, lastProperty, failure);
        catch (IllegalStateException failure)
            throw new BindException(name, type.name, lastProperty, failure);
    }

private:
    ConfigurationProperty lastProperty;

    Descriptor describe(T)()
    {
        if (auto known = descriptors.find(typeNameOf!T))
            return known;
        auto descriptor = descriptorOf!T();
        descriptors.add(descriptor);
        return descriptor;
    }

    bool bindValue(ConfigurationPropertyName name, const Descriptor type, ref Any instance)
    {
        if (isValueType(type))
            return bindScalar(name, type, instance);
        final switch (type.kind)
        {
        case TypeKind.scalar:
        case TypeKind.string_:
        case TypeKind.enum_:
            return bindScalar(name, type, instance);
        case TypeKind.array:
            throw new IllegalStateException("Binding " ~ type.name
                    ~ " needs the descriptor's collection builders, which flint:engine-aot does not provide yet");
        case TypeKind.struct_:
        case TypeKind.class_:
        case TypeKind.interface_:
            return bindDataObject(name, type, instance);
        }
    }

    bool bindScalar(ConfigurationPropertyName name, const Descriptor type, ref Any instance)
    {
        auto property = ConfigurationPropertySources.find(sources, name);
        if (property is null)
            return false;
        lastProperty = property;
        instance = convert(placeholders.resolvePlaceholders(property.getValue()), type);
        return true;
    }

    // JavaBean binding, or value-object binding through the preferred constructor when it takes parameters.
    bool bindDataObject(ConfigurationPropertyName name, const Descriptor type, ref Any instance)
    {
        if (!name.isEmpty() && !ConfigurationPropertySources.containsDescendantOf(sources, name))
            return false;
        if (instance.isNull() && type.constructors.length && type.constructors[0].parameters.length)
            return bindValueObject(name, type, instance);
        bool bound;
        Any target = instance;
        foreach (ref property; type.properties)
        {
            if (property.set is null)
                continue;
            auto propertyType = lookup(property.type);
            if (propertyType is null)
                continue;
            if (target.isNull())
                target = create(name, type);
            Any value = property.get is null ? Any.init : property.get(target);
            if (isValueType(propertyType))
                value = Any.init;
            if (bindValue(name.append(toDashedForm(property.name)), propertyType, value))
            {
                property.set(target, value);
                bound = true;
            }
        }
        if (bound)
            instance = target;
        return bound;
    }

    bool bindValueObject(ConfigurationPropertyName name, const Descriptor type, ref Any instance)
    {
        auto constructor = type.constructors[0];
        Any[] arguments;
        bool bound;
        foreach (ref parameter; constructor.parameters)
        {
            auto parameterType = lookup(parameter.type);
            if (parameterType is null)
                throw new IllegalStateException(
                        "No descriptor for " ~ parameter.type ~ ", parameter '" ~ parameter.name ~ "' of " ~ type.name);
            Any value;
            if (bindValue(name.append(toDashedForm(parameter.name)), parameterType, value))
                bound = true;
            else
                value = defaultFor(parameter.annotations, parameterType, name);
            arguments ~= value;
        }
        if (!bound)
            return false;
        instance = constructor.invoke(arguments);
        return true;
    }

    Any defaultFor(const(typeof(Descriptor.annotations)) annotations, const Descriptor type,
            ConfigurationPropertyName name)
    {
        import std.array : join;
        import flint.engine.aot.descriptor : findAnnotation;

        if (auto annotation = findAnnotation(annotations, typeNameOf!DefaultValue))
        {
            const values = annotation.value.get!DefaultValue.value;
            if (type.kind == TypeKind.struct_ || type.kind == TypeKind.class_)
                return create(name, type);
            return convert(values.join(","), type);
        }
        return Any.init;
    }

    // A descriptor by type name; the converter's own value types need none registered.
    const(Descriptor) lookup(string type)
    {
        if (auto known = descriptors.find(type))
            return known;
        if (type == "core.time.Duration")
        {
            auto duration = new Descriptor(type, TypeKind.struct_);
            descriptors.add(duration);
            return duration;
        }
        return null;
    }

    static bool isValueType(const Descriptor type) pure nothrow @nogc
    {
        return type.kind == TypeKind.scalar || type.kind == TypeKind.string_
            || type.kind == TypeKind.enum_ || type.name == "core.time.Duration";
    }

    Any create(ConfigurationPropertyName name, const Descriptor type)
    {
        if (type.create is null)
            throw new IllegalStateException(
                    "Unable to create instance for " ~ type.name ~ " bound under '" ~ name.toString() ~ "'");
        return type.create();
    }
}

/// Convert configuration text to a value of the scalar, string or enum `type`, as Boot's `BindConverter` with
/// `ApplicationConversionService` does: lenient booleans, numbers in decimal, hex (`0x`, `#`) and with a sign,
/// `Duration` in the simple (`10s`, `500ms`) and ISO-8601 (`PT10S`) styles.
Any convert(string text, const Descriptor type)
{
    import std.string : strip;

    switch (type.name)
    {
    case "string":
        return Any.of(text);
    case "bool":
        return Any.of(parseBoolean(text.strip, type.name));
    case "char":
        if (text.length != 1)
            throw new ConversionFailedException(text, type.name, "can only convert a [String] with length of 1");
        return Any.of(text[0]);
    case "float":
    case "double":
    case "real":
        return Any.of(parseFloating(text.strip, type.name));
    case "core.time.Duration":
        return Any.of(parseDuration(text.strip));
    default:
        if (type.kind == TypeKind.scalar)
            return integral(text.strip, type.name);
        throw new ConversionFailedException(text, type.name, type.kind == TypeKind.enum_
                ? "enum binding needs Any.ofEnum from flint:engine-aot" : "no converter for the type");
    }
}

private bool parseBoolean(string text, string type)
{
    import std.uni : toLower;

    switch (text.toLower)
    {
    case "true":
    case "on":
    case "yes":
    case "1":
        return true;
    case "false":
    case "off":
    case "no":
    case "0":
        return false;
    default:
        throw new ConversionFailedException(text, type, "Invalid boolean value '" ~ text ~ "'");
    }
}

private double parseFloating(string text, string type)
{
    import std.conv : ConvException, to;

    try
        return text.to!double;
    catch (ConvException)
        throw new ConversionFailedException(text, type, "For input string: \"" ~ text ~ "\"");
}

private Any integral(string text, string type)
{
    import std.conv : ConvException, to;

    long value;
    try
        value = parseNumber(text);
    catch (ConvException)
        throw new ConversionFailedException(text, type, "For input string: \"" ~ text ~ "\"");
    bool fits(long low, long high)
    {
        return value >= low && value <= high;
    }

    switch (type)
    {
    case "byte":
        return checked(fits(byte.min, byte.max), Any.of(cast(byte) value), text, type);
    case "ubyte":
        return checked(fits(0, ubyte.max), Any.of(cast(ubyte) value), text, type);
    case "short":
        return checked(fits(short.min, short.max), Any.of(cast(short) value), text, type);
    case "ushort":
        return checked(fits(0, ushort.max), Any.of(cast(ushort) value), text, type);
    case "int":
        return checked(fits(int.min, int.max), Any.of(cast(int) value), text, type);
    case "uint":
        return checked(fits(0, uint.max), Any.of(cast(uint) value), text, type);
    case "long":
        return Any.of(value);
    case "ulong":
        return checked(value >= 0, Any.of(cast(ulong) value), text, type);
    default:
        throw new ConversionFailedException(text, type, "no converter for the type");
    }
}

private Any checked(bool fits, Any value, string text, string type)
{
    if (!fits)
        throw new ConversionFailedException(text, type, "Value out of range. Value:\"" ~ text ~ "\"");
    return value;
}

// spring-core's NumberUtils.parseNumber for integral types: a sign, then `0x`, `0X` or `#` for hex.
private long parseNumber(string text)
{
    import std.algorithm.searching : startsWith;
    import std.conv : to;

    bool negative;
    string digits = text;
    if (digits.startsWith("-") || digits.startsWith("+"))
    {
        negative = digits[0] == '-';
        digits = digits[1 .. $];
    }
    long value;
    if (digits.startsWith("0x") || digits.startsWith("0X"))
        value = digits[2 .. $].to!long(16);
    else if (digits.startsWith("#"))
        value = digits[1 .. $].to!long(16);
    else
        value = digits.to!long;
    return negative ? -value : value;
}

/// Boot's `DurationStyle.detectAndParse`: `10s`, `-5m`, `500` (milliseconds), or ISO-8601 `PT1H30M`.
auto parseDuration(string text)
{
    import std.conv : ConvException, to;
    import std.uni : toLower;

    if (isIsoDuration(text))
        return parseIsoDuration(text);
    size_t split = text.length;
    while (split > 0 && isLetter(text[split - 1]))
        split--;
    long amount;
    try
        amount = text[0 .. split].to!long;
    catch (ConvException)
        throw new ConversionFailedException(text, durationType, "'" ~ text ~ "' is not a valid duration");
    return simpleDuration(amount, text[split .. $].toLower, text);
}

private enum durationType = "core.time.Duration";

private bool isIsoDuration(string text) pure nothrow @nogc
{
    if (text.length == 0)
        return false;
    const start = (text[0] == '-' || text[0] == '+') ? 1 : 0;
    return text.length > start && (text[start] == 'P' || text[start] == 'p');
}

private bool isLetter(char ch) pure nothrow @nogc
{
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

// DurationStyle.Unit: the suffix's unit; no suffix means milliseconds.
private auto simpleDuration(long amount, string suffix, string text)
{
    import core.time : dur;

    static immutable string[] suffixes = ["ns", "us", "", "ms", "s", "m", "h", "d"];
    static immutable string[] units = [
        "nsecs", "usecs", "msecs", "msecs", "seconds", "minutes", "hours", "days"
    ];
    foreach (index, candidate; suffixes)
    {
        if (candidate != suffix)
            continue;
        switch (units[index])
        {
            static foreach (unit; ["nsecs", "usecs", "msecs", "seconds", "minutes", "hours", "days"])
            {
        case unit:
                return dur!unit(amount);
            }
        default:
            break;
        }
    }
    throw new ConversionFailedException(text, durationType, "Unknown unit '" ~ suffix ~ "'");
}

// java.time.Duration.parse: [-+]P[nD][T[nH][nM][n[.f]S]].
private auto parseIsoDuration(string text)
{
    import core.time : Duration;
    import std.conv : ConvException;
    import std.uni : toUpper;

    auto upper = text.toUpper;
    const negative = upper[0] == '-';
    if (upper[0] == '-' || upper[0] == '+')
        upper = upper[1 .. $];
    Duration result;
    bool time;
    size_t start = 1;
    try
    {
        foreach (index; 1 .. upper.length)
        {
            const ch = upper[index];
            if (ch == 'T')
            {
                time = true;
                start = index + 1;
            }
            else if (ch == 'D' || ch == 'H' || ch == 'M' || ch == 'S')
            {
                result += isoComponent(upper[start .. index], ch, time);
                start = index + 1;
            }
        }
    }
    catch (ConvException)
        start = 0;
    if (start != upper.length)
        throw new ConversionFailedException(text, durationType, "'" ~ text ~ "' is not a valid ISO-8601 duration");
    return negative ? -result : result;
}

private auto isoComponent(string number, char unit, bool time)
{
    import core.time : days, hours, minutes, nsecs;
    import std.conv : ConvException, to;

    if (unit == 'S' && time)
        return nsecs(cast(long)(number.to!double * 1_000_000_000));
    if (unit == 'D' && !time)
        return days(number.to!long);
    if (unit == 'H' && time)
        return hours(number.to!long);
    if (unit == 'M' && time)
        return minutes(number.to!long);
    throw new ConvException("misplaced unit");
}
