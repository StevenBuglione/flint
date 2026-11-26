/++
Compiled SpEL for method-level expressions (AOT contract 3, section 9.1).

Flint AOT compiles each SpEL-valued attribute of a method's merged annotations (`@Cacheable(key)`,
`@PreAuthorize`, `@EventListener(condition)`, ...) to a typed D function over an `EvaluationContext`. The runtime
that applies the annotation builds the context over the invocation or event and calls `evaluate`.
+/
module flint.engine.aot.expression;

import flint.engine.aot.any : Any;

@safe:

/// What a compiled expression reads: the invocation's arguments and result, beans, placeholders and root functions.
interface EvaluationContext
{
    /// `#p0`, `#a0` or `#name`: the boxed argument at `index`.
    Any argument(size_t index);
    /// `#result`: the method's result; `Any.init` before the call.
    Any result();
    /// `#root.methodName`.
    string methodName();
    /// A root function such as `hasRole('A')`, `hasAnyRole`, `hasAuthority` or `isAuthenticated()`.
    Any rootFunction(string name, scope Any[] arguments);
    /// A root property such as `authentication`, `principal`, or an event root's `event`.
    Any rootProperty(string name);
    /// `@name`: the bean named `name`.
    Object bean(string name);
    /// `${...}` inside `#{...}`: the resolved placeholder text.
    string placeholder(string text);
}

/// An expression compiled by Flint AOT.
alias CompiledExpression = Any function(EvaluationContext context) @safe;

/++
A `double` literal of compiled SpEL, opaque to constant folding. DMD folds floating-point constants at 80-bit
precision, so a folded `0.1 + 0.2` would print as 0.3 instead of Java's 0.30000000000000004. Every real literal goes
through this call, so each operation on it runs at run time in IEEE double, one rounding per operation as in Java.
+/
pragma(inline, false) double spelDouble(double value) pure nothrow @nogc
{
    return value;
}

/++
SpEL's `^` on integer operands (`OpPower`): Java's `(long) Math.pow(base, exponent)`. The power is computed in
`double`, so a negative exponent truncates toward zero (`2 ^ -1` is 0, `1 ^ -5` is 1), and the conversion saturates
as Java's `d2l` does: NaN is 0, and a result beyond `long`'s range is `long.max` or `long.min`. D's integer `^^`
would instead wrap on overflow and reject a negative exponent.
+/
long spelPowLong(long base, long exponent) pure nothrow @nogc
{
    import std.math.exponential : pow;

    const result = pow(cast(double) base, cast(double) exponent);
    if (result != result)
        return 0;
    if (result >= 0x1p63)
        return long.max;
    if (result <= -0x1p63)
        return long.min;
    return cast(long) result;
}

/++
SpEL's ordering of strings (`<`, `<=`, `>`, `>=`): the sign of Java's `String.compareTo`, which compares UTF-16 code
units. That is code point order, except that a supplementary character (a surrogate pair, lead unit
U+D800..U+DBFF) sorts before U+E000..U+FFFF, where D's operators, comparing UTF-8 bytes, put it after. Malformed
UTF-8 reads as U+FFFD, as `flint.engine.aot.text.decodeUtf8` reads it.
+/
int spelCompareStrings(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    import flint.engine.aot.text : decodeUtf8;

    // The first UTF-16 unit of `c`, and the second for a supplementary character (0 otherwise).
    static uint lead(dchar c) pure nothrow @nogc
    {
        return c < 0x10000 ? c : 0xD800 + ((c - 0x10000) >> 10);
    }

    static uint trail(dchar c) pure nothrow @nogc
    {
        return c < 0x10000 ? 0 : 0xDC00 + ((c - 0x10000) & 0x3FF);
    }

    size_t i, j;
    while (i < a.length && j < b.length)
    {
        const x = decodeUtf8(a, i), y = decodeUtf8(b, j);
        if (x == y)
            continue;
        if (lead(x) != lead(y))
            return lead(x) < lead(y) ? -1 : 1;
        // Same lead unit: both supplementary (a BMP character's lead is itself, never a surrogate).
        return trail(x) < trail(y) ? -1 : 1;
    }
    return i < a.length ? 1 : j < b.length ? -1 : 0;
}

/// `false`, having evaluated `value`: a compiled comparison of a number or boolean with SpEL's `null` (never equal,
/// and ordered after it), which still evaluates its operand as Spring does.
bool spelIsNull(T)(T value) pure nothrow @nogc if (__traits(isArithmetic, T))
{
    return false;
}

/// The `float` counterpart of `spelDouble`, for a literal with the `f` suffix.
pragma(inline, false) float spelFloat(float value) pure nothrow @nogc
{
    return value;
}

unittest
{
    // What Java computes: one double rounding per operation (sol-template's parity corpus).
    assert(spelDouble(0.1) + spelDouble(0.2) == 0.30000000000000004);
    assert(spelDouble(0.1) + spelDouble(0.2) != 0.3);
    const float sum = spelFloat(0.1f) + spelFloat(0.2f);
    assert(sum == 0.3f); // Java's 0.1f + 0.2f is 0.3f, rounded once to float
}

@("spelCompareStrings orders by UTF-16 code units, as String.compareTo")
unittest
{
    static assert(is(typeof(&spelCompareStrings) : int function(scope const(char)[],
            scope const(char)[]) pure nothrow @nogc @safe));
    assert(spelCompareStrings("abc", "abd") < 0 && spelCompareStrings("abd", "abc") > 0);
    assert(spelCompareStrings("abc", "abc") == 0 && spelCompareStrings("", "") == 0);
    assert(spelCompareStrings("ab", "abc") < 0 && spelCompareStrings("abc", "ab") > 0);
    // A surrogate pair (U+1F600) sorts before U+E000 in UTF-16, after it in UTF-8 and code point order.
    assert(spelCompareStrings("\U0001F600", "\uE000") < 0);
    assert("\U0001F600" > "\uE000");
    // Below the surrogate range, both agree.
    assert(spelCompareStrings("\U0001F600", "\uD7FF") > 0);
    assert(spelCompareStrings("\U0001F600", "\U0001F601") < 0);
    assert(spelCompareStrings("é", "z") > 0);
}

@("spelPowLong is Java's (long) Math.pow: truncation toward zero, saturation, NaN to 0")
unittest
{
    static assert(is(typeof(&spelPowLong) : long function(long, long) pure nothrow @nogc @safe));
    assert(spelPowLong(2, 10) == 1024);
    assert(spelPowLong(-3, 3) == -27);
    assert(spelPowLong(2, -1) == 0);
    assert(spelPowLong(1, -5) == 1);
    assert(spelPowLong(-1, -3) == -1);
    assert(spelPowLong(0, 0) == 1);
    assert(spelPowLong(10, 30) == long.max);
    assert(spelPowLong(-10, 31) == long.min);
    assert(spelPowLong(2, 62) == 4_611_686_018_427_387_904L);
}

/// One SpEL-valued attribute of a method's merged annotations.
struct ExpressionSpec
{
    /// The annotation's fully qualified D name, as generated tables spell it.
    string annotation;
    /// The attribute holding the expression (`key`, `condition`, `unless`, `value`).
    string attribute;
    /// The expression's source text, for diagnostics.
    string source;
    /// The compiled expression.
    CompiledExpression evaluate;
}

/// Whether a condition's result means true: a `bool` true, or a string that reads `true` ignoring case
/// (Spring's `Boolean.TRUE.equals(value) || Boolean.parseBoolean(string)`).
bool isTrue(Any value)
{
    if (value.isNull)
        return false;
    if (value.typeName == "bool")
        return value.get!bool;
    if (value.typeName == "string")
    {
        const text = value.get!string;
        if (text.length != 4)
            return false;
        foreach (i, c; "true")
            if ((text[i] | 0x20) != c)
                return false;
        return true;
    }
    return false;
}

unittest
{
    assert(isTrue(Any.of(true)) && !isTrue(Any.of(false)) && !isTrue(Any.init));
    assert(isTrue(Any.of("TRUE")) && isTrue(Any.of("true")) && !isTrue(Any.of("yes")) && !isTrue(Any.of(1)));
}
