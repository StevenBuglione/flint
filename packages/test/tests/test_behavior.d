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
