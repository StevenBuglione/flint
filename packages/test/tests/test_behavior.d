module flint.test.behavior_test;

import flint.test : AssertionFailure, Mock, MockMethod, MockOptions, expect;
import std.algorithm.searching : canFind;
import std.exception : assertThrown, collectException;
import std.traits : ReturnType;

@safe:

@("fluent assertions preserve values and caller location")
unittest
{
    expect([1, 2]).toEqual([1, 2]);
    expect("same").toEqual("same");
    expect(true).toBeTrue();
    expect(false).toBeFalse();
    const line = __LINE__ + 1;
    const mismatch = collectException!AssertionFailure(expect(42).toEqual(43));
    assert(mismatch !is null && mismatch.file == __FILE__ && mismatch.line == line);
    assert(mismatch.msg.canFind("expected 43, received 42"));
    assertThrown!AssertionFailure(expect(double.nan).toEqual(double.nan));
    assertThrown!AssertionFailure(expect(false).toBeTrue());
}

private interface Base
{
    int value() const @safe nothrow @nogc;
}

private interface OtherBase
{
    int value() const @safe nothrow @nogc;
}

private interface Derived : Base, OtherBase
{
    string value(in string key) @safe;
    void mark(ref int input) @safe;
}

static assert(!__traits(compiles, {
        auto mock = Mock!Derived.create();
        mock.returns!(Derived.value)(1);
    }));

private interface BorrowedReference
{
    ref int value() @safe;
}

static assert(!__traits(compiles, { auto mock = Mock!BorrowedReference.create(); }));

private size_t overloadReturning(Value)()
{
    size_t selected = size_t.max;
    static foreach (index, method; __traits(getOverloads, Derived, "value"))
    {
        static if (is(ReturnType!method == Value))
            selected = index;
    }
    return selected;
}

@("generated overloads, inherited duplicates, ref and const methods")
unittest
{
    enum keyOverload = overloadReturning!string();
    enum valueOverload = overloadReturning!int();
    auto mock = Mock!Derived.create();
    mock.returns!(MockMethod!(Derived, "value", keyOverload))("configured value");
    mock.returns!(MockMethod!(Derived, "value", valueOverload))(7);
    mock.returns!(MockMethod!(Derived, "value", valueOverload))(8);
    mock.expects!(Derived.mark)();
    auto instance = mock.instance();
    const Base left = instance;
    const OtherBase right = instance;
    int input;
    input = 7;
    assert(instance.value("key") == "configured value");
    assert(left.value() == 7);
    assert(right.value() == 8);
    instance.mark(input);
    assert(input == 7);
    mock.verify();
}

@("strict verification, bounds, ownership and reset")
unittest
{
    auto mock = Mock!Base.create(MockOptions(true, 2));
    auto copy = mock;
    copy.returns!(Base.value)(3);
    assertThrown!AssertionFailure(mock.verify());
    auto instance = copy.instance();
    assert(instance.value() == 3);
    mock.verify();
    assert(instance.value() == int.init);
    const unexpected = collectException!AssertionFailure(copy.verify());
    assert(unexpected !is null && unexpected.msg.canFind("unexpected call"));
    instance.value();
    const overflow = collectException!AssertionFailure(mock.verify());
    assert(overflow !is null && overflow.msg.canFind("capacity"));

    copy.reset();
    mock.verify();
    mock.returns!(Base.value)(5);
    assert(instance.value() == 5);
    mock.verify();

    auto relaxed = Mock!Base.create(MockOptions(false, 1));
    assert(relaxed.instance().value() == int.init);
    relaxed.verify();
}

@("type-specific equality diagnostics for strings, arrays and NaN")
unittest
{
    const text = collectException!AssertionFailure(expect("a\nb").toEqual("a b"));
    assert(text !is null && text.msg == `expected "a b", received "a\nb"`, text.msg);
    const empty = collectException!AssertionFailure(expect("").toEqual(" "));
    assert(empty !is null && empty.msg == `expected " ", received ""`, empty.msg);
    const element = collectException!AssertionFailure(expect([1, 2, 3]).toEqual([1, 5, 3]));
    assert(element !is null
            && element.msg == "expected [1, 5, 3], received [1, 2, 3] (first difference at index 1)", element.msg);
    const length = collectException!AssertionFailure(expect([1, 2]).toEqual([1, 2, 3]));
    assert(length !is null && length.msg == "expected [1, 2, 3], received [1, 2] (lengths 3 and 2)", length.msg);
    const words = collectException!AssertionFailure(expect(["x", "y"]).toEqual(["x", "z"]));
    assert(words !is null
            && words.msg == `expected ["x", "z"], received ["x", "y"] (first difference at index 1)`, words.msg);
    const nan = collectException!AssertionFailure(expect(double.nan).toEqual(double.nan));
    assert(nan !is null && nan.msg.canFind("NaN never compares equal"), nan.msg);
    const real_ = collectException!AssertionFailure(expect(1.5f).toEqual(2.5f));
    assert(real_ !is null && real_.msg == "expected 2.5, received 1.5", real_.msg);
    expect(-0.0).toEqual(0.0);
    expect(cast(string) null).toEqual("");
}

@("missing expectation, zero calls and verify after reset report the method")
unittest
{
    auto mock = Mock!Base.create();
    mock.verify();
    mock.returns!(Base.value)(4);
    const missing = collectException!AssertionFailure(mock.verify());
    assert(missing !is null && missing.msg == "value expected 1 call(s), received 0", missing.msg);
    mock.reset();
    mock.verify();
    auto instance = mock.instance();
    assert(instance.value() == int.init);
    const unconfigured = collectException!AssertionFailure(mock.verify());
    assert(unconfigured !is null && unconfigured.msg == "unexpected call to value", unconfigured.msg);
    mock.reset();
    mock.verify();
    mock.returns!(Base.value)(9);
    mock.returns!(Base.value)(10);
    assert(instance.value() == 9);
    const short_ = collectException!AssertionFailure(mock.verify());
    assert(short_ !is null && short_.msg == "value expected 2 call(s), received 1", short_.msg);
    assert(instance.value() == 10);
    mock.verify();
    assertThrown!Exception(mock.returns!(Base.value)(11));
}

private interface NoGcService
{
    int next(int input) @safe nothrow @nogc;
    void signal() @safe nothrow @nogc;
}

private int callNoGc(NoGcService service) @safe nothrow @nogc
{
    service.signal();
    return service.next(1);
}

@("generated mocks keep @safe nothrow @nogc interface methods callable from @nogc code")
unittest
{
    auto mock = Mock!NoGcService.create(MockOptions(true, 4));
    mock.expects!(NoGcService.signal)();
    mock.returns!(NoGcService.next)(12);
    assert(callNoGc(mock.instance()) == 12);
    mock.verify();
    assert(callNoGc(mock.instance()) == int.init);
    const failure = collectException!AssertionFailure(mock.verify());
    assert(failure !is null && failure.msg.canFind("unexpected call to signal"), failure.msg);
}

@("runner UTF-8 decoding matches std.utf replacement decoding")
unittest
{
    import flint.test.internal.runner : decodeReplacing;
    import std.utf : UseReplacementDchar, decode;

    static void same(scope const(char)[] text) @safe
    {
        size_t expectedIndex;
        size_t actualIndex;
        const expected = decode!(UseReplacementDchar.yes)(text, expectedIndex);
        const actual = decodeReplacing(text, actualIndex);
        assert(expected == actual && expectedIndex == actualIndex);
    }

    char[4] buffer;
    foreach (first; 0 .. 256)
    {
        buffer[0] = cast(char) first;
        same(buffer[0 .. 1]);
        foreach (second; 0 .. 256)
        {
            buffer[1] = cast(char) second;
            same(buffer[0 .. 2]);
        }
    }
    // Lead, continuation and boundary bytes of every sequence length, including overlong, surrogate,
    // beyond-U+10FFFF, truncated and five- and six-unit forms.
    static immutable ubyte[] edges = [
        0x00, 0x41, 0x7F, 0x80, 0x8F, 0x90, 0x9F, 0xA0, 0xBF, 0xC0, 0xC1, 0xC2, 0xDF, 0xE0, 0xED,
        0xEF, 0xF0, 0xF4, 0xF5, 0xF7, 0xF8, 0xFB, 0xFC, 0xFE, 0xFF
    ];
    foreach (a; edges)
        foreach (b; edges)
            foreach (c; edges)
            {
                buffer[0] = cast(char) a;
                buffer[1] = cast(char) b;
                buffer[2] = cast(char) c;
                same(buffer[0 .. 3]);
                foreach (d; edges)
                {
                    buffer[3] = cast(char) d;
                    same(buffer[0 .. 4]);
                }
            }
}

@("mock and runner decimal text matches std.conv")
unittest
{
    import flint.test.internal.mocks : decimal;
    import std.conv : to;

    static immutable ulong[] values = [
        0, 1, 9, 10, 99, 100, 479, 4_294_967_295, 4_294_967_296, ulong.max - 1, ulong.max
    ];
    foreach (value; values)
        assert(decimal(value) == value.to!string, value.to!string);
}
