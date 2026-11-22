module flint.test.internal.mocks;

import std.conv : to;
import std.format : format;
import std.meta : AliasSeq, aliasSeqOf, staticMap;
import std.traits : FA = FunctionAttribute, PSC = ParameterStorageClass, Parameters, ReturnType,
    Variadic, functionAttributes, functionLinkage, ParameterStorageClassTuple, variadicFunctionStyle;
import std.typecons : Tuple;

@safe:

private template sameSignature(alias left, alias right)
{
    enum sameSignature = __traits(identifier, left) == __traits(identifier, right) && is(typeof(left) == typeof(right));
}

private bool firstVirtual(size_t position, Methods...)()
{
    alias method = Methods[position];
    if (!__traits(isVirtualMethod, method))
        return false;
    static foreach (prior; 0 .. position)
    {
        if (__traits(identifier, method) == __traits(identifier, Methods[prior])
                && is(typeof(method) == typeof(Methods[prior])))
            return false;
    }
    return true;
}

private size_t[] indices(size_t count)
{
    auto result = new size_t[count];
    foreach (i, ref index; result)
        index = i;
    return result;
}

private template methodsOf(Contract)
{
    static assert(is(Contract == interface), "Mock requires an interface");
    template overloads(string name)
    {
        alias overloads = __traits(getOverloads, Contract, name);
    }

    private alias candidates = staticMap!(overloads, __traits(allMembers, Contract));
    template unique(size_t index)
    {
        static if (firstVirtual!(index, candidates)())
            alias unique = AliasSeq!(candidates[index]);
        else
            alias unique = AliasSeq!();
    }

    alias methodsOf = staticMap!(unique, aliasSeqOf!(indices(candidates.length)));
    static assert(methodsOf.length <= 64, "Mock supports up to 64 distinct methods");
}

package(flint.test) struct SelectedMethod(Contract, string name, size_t overload)
{
    alias Owner = Contract;
    private alias Overloads = __traits(getOverloads, Contract, name);
    // Aliases resolve before struct-scope static asserts, so guard the index lookup itself.
    static if (overload < Overloads.length)
        alias Method = Overloads[overload];
    else
        static assert(false, "Mock overload index is out of range");
    enum explicitlySelected = true;
}

private template indexOf(alias selected, size_t index, Methods...)
{
    static if (Methods.length == 0)
        enum indexOf = size_t.max;
    else static if (sameSignature!(selected, Methods[0]))
        enum indexOf = index;
    else
        enum indexOf = indexOf!(selected, index + 1, Methods[1 .. $]);
}

package(flint.test) template methodIndex(Contract, alias selection)
{
    static if (is(selection) && __traits(hasMember, selection, "explicitlySelected"))
    {
        static assert(is(selection.Owner == Contract), "mock overload belongs to a different interface");
        alias method = selection.Method;
    }
    else
    {
        alias method = selection;
        enum name = __traits(identifier, method);
        static assert(__traits(getOverloads, Contract, name).length == 1,
                "select overloaded methods with MockMethod!(Interface, name, overload)");
    }
    enum methodIndex = indexOf!(method, 0, methodsOf!Contract);
    static assert(methodIndex != size_t.max, "method is not in the mock interface");
}

private string emitMethods(Methods...)()
{
    string source;
    static foreach (index, method; Methods)
    {
        {
            enum name = __traits(identifier, method);
            enum attributes = functionAttributes!method;
            enum unsupported = FA.pure_ | FA.ref_ | FA.return_ | FA.scope_ | FA.immutable_
                | FA.inout_ | FA.shared_ | FA.live;
            static assert((attributes & unsupported) == 0 && variadicFunctionStyle!method == Variadic.no
                    && functionLinkage!method == "D", "unsupported mock method qualifiers on " ~ name);
            enum suffix = (attributes & FA.const_ ? " const" : "") ~ (attributes & FA.nothrow_
                        ? " nothrow" : "") ~ (attributes & FA.nogc
                        ? " @nogc" : "") ~ (attributes & FA.property ? " @property" : "");
            enum idx = to!string(index);
            source ~= "override ReturnType!(MethodList[" ~ idx ~ "]) " ~ name ~ "(";
            static foreach (parameter, mode; ParameterStorageClassTuple!method)
            {
                {
                    static assert(mode == PSC.none || mode == PSC.ref_ || mode == PSC.in_,
                            "mock parameters must be value, ref, or in");
                    if (parameter != 0)
                        source ~= ", ";
                    static if (mode == PSC.ref_)
                        source ~= "ref ";
                    else static if (mode == PSC.in_)
                        source ~= "in ";
                    enum p = to!string(parameter);
                    source ~= "Parameters!(MethodList[" ~ idx ~ "])[" ~ p ~ "] arg" ~ p;
                }
            }
            source ~= ") @safe" ~ suffix ~ " { ";
            static if (!is(ReturnType!method == void))
                source ~= "return ";
            source ~= "flintState().invoke!(" ~ idx ~ ")(); }\n";
        }
    }
    return source;
}

private struct Plan(alias method)
{
    alias Value = ReturnType!method;
    static if (!is(Value == void))
        Value[] values;
    size_t expected;
    size_t observed;
}

package(flint.test) final class MockState(Contract)
{
    private alias MethodList = methodsOf!Contract;
    private alias Plans = Tuple!(staticMap!(Plan, MethodList));

    // TLS provides mutable state for const methods without casting away their qualifiers.
    private static MockState[] active;
    private size_t entry;
    private size_t owners = 1;
    private Concrete concrete;
    private Plans plans;
    private bool strict;
    private uint[] callLog;
    private size_t callCount;
    private size_t expectedCount;
    private string violation;

    private static final class Concrete : Contract
    {
        private size_t entry;

        this(size_t entry)
        {
            this.entry = entry;
        }

        private MockState flintState() const nothrow @nogc
        {
            if (entry >= active.length || active[entry] is null || active[entry].concrete !is this)
                assert(0, "mock instance used after release or outside its owner thread");
            return active[entry];
        }

        mixin(emitMethods!MethodList());
    }

    static MockState create(bool strict, uint capacity)
    {
        if (capacity == 0)
            throw new Exception("mock call capacity must be positive");
        auto state = new MockState;
        state.strict = strict;
        state.callLog = new uint[capacity];
        while (state.entry < active.length && active[state.entry]!is null)
            ++state.entry;
        state.concrete = new Concrete(state.entry);
        if (state.entry == active.length)
            active ~= state;
        else
            active[state.entry] = state;
        return state;
    }

    @property bool onOwner() nothrow @nogc
    {
        return entry < active.length && active[entry] is this;
    }

    void retain() nothrow @nogc
    {
        if (!onOwner || owners == size_t.max)
            assert(0, "mock ownership invariant");
        ++owners;
    }

    void release() nothrow @nogc
    {
        if (!onOwner || owners == 0)
            assert(0, "mock ownership invariant");
        if (--owners == 0)
            active[entry] = null;
    }

    @property Contract implementation() nothrow @nogc
    {
        return concrete;
    }

    private void requireConfiguration()
    {
        if (callCount != 0)
            throw new Exception("configure the mock before its first call or after reset");
        if (expectedCount == callLog.length)
            throw new Exception("too many configured mock calls");
    }

    void configure(size_t index, T)(T result)
    {
        alias Value = ReturnType!(MethodList[index]);
        static assert(!is(Value == void) && is(T : Value), "return value must match the mock method type");
        requireConfiguration();
        plans[index].values ~= result;
        ++plans[index].expected;
        ++expectedCount;
    }

    void configureVoid(size_t index)()
    {
        static assert(is(ReturnType!(MethodList[index]) == void), "expects requires a void method");
        requireConfiguration();
        ++plans[index].expected;
        ++expectedCount;
    }

    ReturnType!(MethodList[index]) invoke(size_t index)()
    {
        alias Value = ReturnType!(MethodList[index]);
        if (callCount == callLog.length)
        {
            violation = "mock call log capacity exceeded";
            static if (!is(Value == void))
                return Value.init;
            else
                return;
        }
        callLog[callCount++] = cast(uint) index;
        auto plan = &plans[index];
        const call = plan.observed++;
        if (call >= plan.expected)
        {
            if (strict && violation.length == 0)
                violation = "unexpected call to " ~ __traits(identifier, MethodList[index]);
            static if (!is(Value == void))
                return Value.init;
            else
                return;
        }
        static if (!is(Value == void))
            return plan.values[call];
    }

    string verify()
    {
        if (violation.length != 0)
            return violation;
        static foreach (index, method; MethodList)
        {
            {
                const expected = plans[index].expected;
                const observed = plans[index].observed;
                if (observed < expected)
                    return format!"%s expected %s call(s), received %s"(__traits(identifier,
                            method), expected, observed);
            }
        }
        return null;
    }

    void reset()
    {
        plans = Plans.init;
        callCount = 0;
        expectedCount = 0;
        violation = null;
    }
}

version (unittest)
{
    private interface GeneratedProbe
    {
        int value() const @safe nothrow @nogc;
    }

    // Instantiate the generator for structural audits of compiler-emitted source.
    @("generated const method satisfies the original interface")
    unittest
    {
        auto mock = MockState!GeneratedProbe.create(true, 2);
        scope (exit)
            mock.release();
        mock.configure!0(7);
        const GeneratedProbe instance = mock.implementation;
        assert(instance.value() == 7);
        assert(mock.verify().length == 0);
    }
}
