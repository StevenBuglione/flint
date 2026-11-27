/++
`java.lang` as Spring's APIs expose it (rulebook R8 and R11).

$(UL
    $(LI The exception hierarchy keeps Java's names and shape, with `RuntimeException : Exception` (R8). Java's
        checked `Exception` is D's `Exception`; `throws` clauses are dropped (deviation D-8). Each exception keeps
        Java's `getMessage`, `getCause`, `initCause` and the four-argument constructor whose
        `writableStackTrace = false` skips stack-trace capture, which framework control-flow exceptions use
        (ADR-030 section 4).)
    $(LI `mixin JavaObject;` maps `equals`, `hashCode` and `compareTo` onto D's `opEquals`, `toHash` and `opCmp`
        (R11). Free functions `equals` and `hashCode` give every class Java's identity defaults through UFCS.)
    $(LI `Runnable`, `Comparable`, `Iterable` and `AutoCloseable`, and the parsing statics of `Integer`, `Long`,
        `Boolean` and `Double` that Spring's converters call.)
)
+/
module flint.java.lang;

public import flint.java.lang.boolean : Boolean;
public import flint.java.lang.charsequence : CharSequence;
public import flint.java.lang.error : AssertionError, Error_;
public import flint.java.lang.illegalmonitorstateexception : IllegalMonitorStateException;
public import flint.java.lang.integer : Integer;
public import flint.java.lang.interruptedexception : InterruptedException;
public import flint.java.lang.long_ : Long;
public import flint.java.lang.nullpointerexception : NullPointerException;
public import flint.java.lang.javaobject : JavaObject;
public import flint.java.lang.runnable : Runnable;
public import flint.java.lang.runtimeexception : IllegalArgumentException, IllegalStateException,
    JavaExceptionConstructors, RuntimeException, javaToString;
public import flint.java.lang.system : System;

import flint.engine.aot.objects : objectEquals, objectToHash, objectToString;
public import flint.java.classref : ClassRef, classOf; // a leaf, so annotation-only clients skip this module
import flint.java.util : Iterator; // module scope: a template-scoped import breaks -i builds (forward references)
import flint.engine.aot.any : Any;
import flint.java.util.formatter : formatJava;

@safe:
package(flint) import flint.java.lang.character.decimaldigits : javaDecimalDigit;

// ---------------------------------------------------------------------------------------------------------------
// Exceptions (R8)

/// Thrown when an operation is not supported, such as a write to an unmodifiable collection.
class UnsupportedOperationException : RuntimeException
{
    mixin JavaExceptionConstructors;
}

/// Thrown when a cast is not possible.
class ClassCastException : RuntimeException
{
    mixin JavaExceptionConstructors;
}

/// Thrown on an exceptional arithmetic condition, such as integer division by zero.
class ArithmeticException : RuntimeException
{
    mixin JavaExceptionConstructors;
}

/// Thrown when an index is out of range.
class IndexOutOfBoundsException : RuntimeException
{
    /// No message.
    this() pure nothrow
    {
        super();
    }

    /// `message`, with a cause that can still be initialized.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
    }

    /// `message` and an initialized `cause`.
    this(string message, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }

    /// Select the cause overload when the caller supplies a null literal.
    this(string message, typeof(null), string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        this(message, cast(Throwable) null, file, line);
    }

    /// Java's `IndexOutOfBoundsException(int index)`: "Index out of range: " and the index.
    this(long index, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Index out of range: " ~ decimal(index), file, line);
    }
}

/// Thrown when a string cannot be converted to a number.
class NumberFormatException : IllegalArgumentException
{
    mixin JavaExceptionConstructors;

    /// Java's message for unparsable input: `For input string: "s"`.
    static NumberFormatException forInputString(string s, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        return new NumberFormatException("For input string: \"" ~ s ~ "\"", file, line);
    }
}

/// Thrown when an instance of an abstract class or an interface would be created.
class InstantiationException : RuntimeException
{
    mixin JavaExceptionConstructors;
}

// ---------------------------------------------------------------------------------------------------------------
// Core interfaces

/// Java's `AutoCloseable`: a resource released by `close`.
interface AutoCloseable
{
    /// Release the resource.
    void close();
}

/// Java's `Iterable`: a source of an `Iterator`, usable in `foreach`.
interface Iterable(T)
{

    /// An iterator over the elements.
    Iterator!T iterator();

    /// Call `action` for each element, in iteration order.
    void forEach(void delegate(T) @safe action);

    /// `foreach (e; iterable)`.
    int opApply(scope int delegate(T) @safe dg);
}

/// Java's `Comparable`: a natural ordering.
interface Comparable(T)
{
    /// Negative, zero or positive as this is less than, equal to or greater than `other`.
    int compareTo(T other);
}

// ---------------------------------------------------------------------------------------------------------------
// Object methods (R11)

/// Java's `a.equals(b)` for any class or interface reference through UFCS: the class's `opEquals` (identity
/// unless overridden). Interfaces do not convert to `Object` implicitly in D, hence the template.
bool equals(A, B)(A a, B b)
        if ((is(A == class) || is(A == interface)) && (is(B == class) || is(B == interface)))
{
    return objectEquals(cast(Object) a, cast(Object) b);
}

/// Java's `o.hashCode()` for any class or interface reference through UFCS: its `toHash`, folded to an `int`.
int hashCode(T)(T o) nothrow if (is(T == class) || is(T == interface))
{
    return cast(int) objectToHash(cast(Object) o);
}

/// Java's `Objects.equals` semantics for any `T`: `objectEquals` for references, `==` for values.
bool javaEquals(T)(T a, T b)
{
    static if (is(T == class) || is(T == interface))
        return objectEquals(cast(Object) a, cast(Object) b);
    else
        return a == b;
}

// ---------------------------------------------------------------------------------------------------------------
// String.valueOf and boxed-number statics

/++
Java's `String` statics that have no D counterpart: `String.format`. A `string` is Java's `String` (R14); this
struct only namespaces the static methods, so `String.format(template, name)` reads as in Java.
+/
struct String
{
    @disable this();

    /// `String.format(format, args...)`: Java's `Formatter` syntax (`flint.java.util.formatter`). The arguments
    /// are boxed on the stack and formatted by one non-template engine (rule R7), not by `std.format`.
    static string format(Args...)(string format, Args args)
    {
        Any[Args.length] boxed;
        static foreach (i; 0 .. Args.length)
            boxed[i] = Any.of(args[i]);
        return formatJava(format, boxed[]);
    }
}

/// Java's `String.valueOf`: `"null"` for null, decimal numbers, `true`/`false`, and `toString()` otherwise.
string valueOf(T)(T value)
{
    static if (is(T == class) || is(T == interface))
        return objectToString(cast(Object) value);
    else static if (is(T : const(char)[]))
        return value is null ? "null" : value.idup;
    else static if (is(T == bool))
        return value ? "true" : "false";
    else static if (is(T == float))
        return floatToString(value);
    else static if (__traits(isFloating, T))
        return doubleToString(value);
    else static if (is(T == struct) && is(typeof(value.toString()) : string))
        return value.toString(); // not std.conv, whose struct path instantiates all of std.format
    else static if (is(T : const(string)[]))
    {
        import flint.java.internal.stringliteral : stringArrayLiteral;

        // Keep the compiler's idup instance in the caller so it does not pull unrelated Java archive members.
        return stringArrayLiteral(value).idup;
    }
    else
        return scalarValueOf(value);
}

// `valueOf` for the remaining scalars, through flint.engine.aot.text rather than std.conv (ADR-030 section 5).
private string scalarValueOf(T)(T value)
{
    import flint.engine.aot.text : decimal, enumName, utf8;

    static if (is(T Base == enum) && __traits(isIntegral, Base))
        return enumName(value);
    else static if (is(immutable T == immutable char))
    {
        string unit = [value]; // the code unit as it is, as std.conv appends it
        return unit;
    }
    else static if (is(immutable T == immutable wchar) || is(immutable T == immutable dchar))
    {
        const text = utf8(value);
        return text is null ? "\uFFFD" : text;
    }
    else static if (__traits(isIntegral, T) && __traits(isUnsigned, T))
        return decimal(cast(ulong) value);
    else static if (__traits(isIntegral, T))
        return decimal(cast(long) value);
    else
    {
        import std.conv : to;

        return value.to!string;
    }
}

/// Java's `Double.toString` (JDK 19 and later): the shortest round-trip digits in the JDK's layout, from
/// `flint.serde.java_number` (checked against OpenJDK 21).
string doubleToString(double value) pure nothrow
{
    import flint.serde.java_number : javaDoubleString;

    return javaDoubleString(value);
}

/// Java's `Float.toString`.
string floatToString(float value) pure nothrow
{
    import flint.serde.java_number : javaFloatString;

    return javaFloatString(value);
}

private string decimal(long value) pure nothrow
{
    if (value == 0)
        return "0";
    const negative = value < 0;
    ulong magnitude = negative ? -(cast(ulong) value) : cast(ulong) value;
    char[20] buffer;
    size_t position = buffer.length;
    while (magnitude)
    {
        buffer[--position] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    return (negative ? "-" : "") ~ buffer[position .. $].idup;
}

/// Java's `Double` statics.
struct Double
{
    /// Parse a decimal floating-point number, trimming ASCII whitespace as Java does.
    /// Throws `NumberFormatException`.
    static double parseDouble(string s)
    {
        import flint.engine.aot.text : tryParseDouble;

        size_t start, end = s.length;
        while (start < end && s[start] <= ' ')
            start++;
        while (end > start && s[end - 1] <= ' ')
            end--;
        auto text = s[start .. end];
        if (text.length && (text[$ - 1] == 'd' || text[$ - 1] == 'D' || text[$ - 1] == 'f' || text[$ - 1] == 'F'))
            text = text[0 .. $ - 1];
        if (text.length == 0)
            throw new NumberFormatException(s.length ? "For input string: \"" ~ s ~ "\"" : "empty String");
        const parsed = tryParseDouble(text);
        if (!parsed.ok)
            throw NumberFormatException.forInputString(s);
        return parsed.value;
    }

    /// Java's `Double.toString`.
    static string toString(double d)
    {
        return doubleToString(d);
    }
}

/// Java's `String.hashCode`: `s[0]*31^(n-1) + ... + s[n-1]` over UTF-16 code units.
int stringHashCode(scope const(char)[] s) pure nothrow @nogc
{
    int h;
    size_t i;
    while (i < s.length)
    {
        dchar c = s[i];
        size_t width = 1;
        if (c >= 0x80)
        {
            if ((c & 0xE0) == 0xC0 && i + 1 < s.length)
            {
                c = ((c & 0x1F) << 6) | (s[i + 1] & 0x3F);
                width = 2;
            }
            else if ((c & 0xF0) == 0xE0 && i + 2 < s.length)
            {
                c = ((c & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F);
                width = 3;
            }
            else if ((c & 0xF8) == 0xF0 && i + 3 < s.length)
            {
                c = ((c & 0x07) << 18) | ((s[i + 1] & 0x3F) << 12) | ((s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F);
                width = 4;
            }
        }
        if (c >= 0x10000)
        {
            h = 31 * h + cast(int)(0xD800 + ((c - 0x10000) >> 10));
            h = 31 * h + cast(int)(0xDC00 + ((c - 0x10000) & 0x3FF));
        }
        else
            h = 31 * h + cast(int) c;
        i += width;
    }
    return h;
}

/// Java's `hashCode()` of a value: `String.hashCode` for strings, the boxed type's rule for scalars,
/// `hashCode()` for classes that declare it, and `toHash` otherwise.
int javaHashCode(T)(T value)
{
    static if (is(T : const(char)[]))
        return stringHashCode(value);
    else static if (is(T == bool))
        return Boolean.hashCode(value);
    else static if (is(T == long) || is(T == ulong))
        return Long.hashCode(cast(long) value);
    else static if (__traits(isIntegral, T) || is(T == char) || is(T == wchar) || is(T == dchar))
        return cast(int) value;
    else static if (__traits(isFloating, T))
    {
        const bits = doubleBits(cast(double) value);
        return cast(int)(bits ^ (bits >>> 32));
    }
    else static if (is(T == class) || is(T == interface))
    {
        if (value is null)
            return 0;
        static if (__traits(hasMember, T, "hashCode") && is(typeof(value.hashCode()) : int))
            return value.hashCode();
        else
            return cast(int) objectToHash(cast(Object) value);
    }
    else static if (__traits(hasMember, T, "hashCode"))
        return value.hashCode();
    else
        return cast(int) hashOf(value);
}

private ulong doubleBits(double value) pure nothrow @nogc
{
    if (value != value)
        return 0x7ff8000000000000UL; // Java's canonical NaN
    union Bits
    {
        double d;
        ulong u;
    }

    Bits bits;
    bits.d = value;
    return bits.u;
}
