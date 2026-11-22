module flint.test.internal.mocks;

@safe:

// Built-in alias sequence: std.meta's helpers would add their own instantiations for every mock.
private alias Seq(T...) = T;

// The function attribute bits of std.traits.FunctionAttribute, decoded here without its per-method templates.
private enum Attribute : uint
{
    pure_ = 1 << 0,
    nothrow_ = 1 << 1,
    ref_ = 1 << 2,
    property = 1 << 3,
    trusted = 1 << 4,
    safe = 1 << 5,
    nogc = 1 << 6,
    system = 1 << 7,
    const_ = 1 << 8,
    immutable_ = 1 << 9,
    inout_ = 1 << 10,
    shared_ = 1 << 11,
    return_ = 1 << 12,
    scope_ = 1 << 13,
    live = 1 << 14,
}

// The parameter storage bits of std.traits.ParameterStorageClass.
private enum Storage : uint
{
    none = 0,
    in_ = 1 << 0,
    ref_ = 1 << 1,
    out_ = 1 << 2,
    lazy_ = 1 << 3,
    scope_ = 1 << 4,
    return_ = 1 << 5,
}

// Same mapping as std.traits.functionAttributes over `__traits(getFunctionAttributes)`.
private uint attributeFlags(scope const string[] attributes...) pure nothrow
{
    uint flags;
    foreach (attribute; attributes)
    {
        switch (attribute)
        {
        case "pure":
            flags |= Attribute.pure_;
            break;
        case "nothrow":
            flags |= Attribute.nothrow_;
            break;
        case "ref":
            flags |= Attribute.ref_;
            break;
        case "@property":
            flags |= Attribute.property;
            break;
        case "@trusted":
            flags |= Attribute.trusted;
            break;
        case "@safe":
            flags |= Attribute.safe;
            break;
        case "@nogc":
            flags |= Attribute.nogc;
            break;
        case "@system":
            flags |= Attribute.system;
            break;
        case "const":
            flags |= Attribute.const_;
            break;
        case "immutable":
            flags |= Attribute.immutable_;
            break;
        case "inout":
            flags |= Attribute.inout_;
            break;
        case "shared":
            flags |= Attribute.shared_;
            break;
        case "return":
            flags |= Attribute.return_;
            break;
        case "scope":
            flags |= Attribute.scope_;
            break;
        case "@live":
            flags |= Attribute.live;
            break;
        default:
            assert(0, attribute);
        }
    }
    return flags;
}

// Same mapping as std.traits.ParameterStorageClassTuple over `__traits(getParameterStorageClasses)`.
private uint storageFlags(scope const string[] classes...) pure nothrow
{
    uint flags;
    foreach (storage; classes)
    {
        switch (storage)
        {
        case "scope":
            flags |= Storage.scope_;
            break;
        case "in":
            flags |= Storage.in_;
            break;
        case "out":
            flags |= Storage.out_;
            break;
        case "ref":
            flags |= Storage.ref_;
            break;
        case "lazy":
            flags |= Storage.lazy_;
            break;
        case "return":
            flags |= Storage.return_;
            break;
        default:
            assert(0, storage);
        }
    }
    if (flags == (Storage.ref_ | Storage.return_))
        flags = Storage.return_;
    return flags;
}

/// Decimal text of an unsigned value, shared by generated source and diagnostics.
package(flint.test) string decimal(ulong value) pure nothrow
{
    char[20] digits;
    size_t start = digits.length;
    do
    {
        digits[--start] = "0123456789"[value % 10];
        value /= 10;
    }
    while (value != 0);
    return digits[start .. $].idup;
}

// `__traits(getOverloads, Contract, name)` for every member name, as one alias sequence.
private string overloadList(scope const string[] names) pure
{
    string source;
    foreach (index, name; names)
        source ~= (index == 0 ? "" : ", ") ~ "__traits(getOverloads, Contract, \"" ~ name ~ "\")";
    return source;
}

// Selects each candidate that is the first virtual method with its name and type. Function types are equal
// exactly when their mangled names are, so the comparison needs no instantiation per pair.
private string firstVirtuals(scope const string[] names, scope const string[] types, scope const bool[] virtuals) pure
{
    string selection;
    foreach (position; 0 .. names.length)
    {
        bool first = virtuals[position];
        foreach (prior; 0 .. position)
        {
            if (names[position] == names[prior] && types[position] == types[prior])
                first = false;
        }
        if (first)
            selection ~= (selection.length == 0 ? "" : ", ") ~ "candidates[" ~ decimal(position) ~ "]";
    }
    return selection;
}

private template methodsOf(Contract)
{
    static assert(is(Contract == interface), "Mock requires an interface");
    mixin("private alias candidates = Seq!(" ~ overloadList([__traits(allMembers, Contract)]) ~ ");");
    private enum selection = () {
        string[candidates.length] names;
        string[candidates.length] types;
        bool[candidates.length] virtuals;
        static foreach (index, candidate; candidates)
        {
            names[index] = __traits(identifier, candidate);
            types[index] = typeof(candidate).mangleof;
            virtuals[index] = __traits(isVirtualMethod, candidate);
        }
        return firstVirtuals(names[], types[], virtuals[]);
    }();
    mixin("alias methodsOf = Seq!(" ~ selection ~ ");");
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

// Position of the method with the selected name and mangled type: one flat scan per lookup.
private size_t findMethod(scope const string[] names, scope const string[] types, string name, string type) pure
{
    foreach (index; 0 .. names.length)
    {
        if (names[index] == name && types[index] == type)
            return index;
    }
    return size_t.max;
}

private enum unsupportedAttributes = Attribute.pure_ | Attribute.ref_ | Attribute.return_
    | Attribute.scope_ | Attribute.immutable_ | Attribute.inout_ | Attribute.shared_ | Attribute.live;

// Same acceptance as std.traits.variadicFunctionStyle == Variadic.no.
private bool notVariadic(string style) pure nothrow
{
    return style != "stdarg" && style != "argptr" && style != "typesafe";
}

// Source of one override; `Plans[index]` carries the method's return and parameter types.
private string methodSource(size_t index, string name, uint attributes, bool valued, scope const uint[] modes) pure
{
    const slot = decimal(index);
    string source = "override Plans[" ~ slot ~ "].Value " ~ name ~ "(";
    foreach (parameter, mode; modes)
    {
        if (parameter != 0)
            source ~= ", ";
        if (mode == Storage.ref_)
            source ~= "ref ";
        else if (mode == Storage.in_)
            source ~= "in ";
        const position = decimal(parameter);
        source ~= "Plans[" ~ slot ~ "].Params[" ~ position ~ "] arg" ~ position;
    }
    source ~= ") @safe";
    if (attributes & Attribute.const_)
        source ~= " const";
    if (attributes & Attribute.nothrow_)
        source ~= " nothrow";
    if (attributes & Attribute.nogc)
        source ~= " @nogc";
    if (attributes & Attribute.property)
        source ~= " @property";
    source ~= valued ? " { return " : " { ";
    source ~= "flintState().invoke!(" ~ slot ~ ")(); }\n";
    return source;
}

private string joined(scope const string[] parts) pure
{
    string source;
    foreach (part; parts)
        source ~= part;
    return source;
}

private string emitMethods(Methods...)()
{
    string[Methods.length] sources;
    static foreach (index, method; Methods)
    {
        {
            enum name = __traits(identifier, method);
            enum attributes = attributeFlags(__traits(getFunctionAttributes, method));
            static assert((attributes & unsupportedAttributes) == 0 && notVariadic(__traits(getFunctionVariadicStyle,
                    typeof(method))) && __traits(getLinkage, typeof(method)) == "D",
                    "unsupported mock method qualifiers on " ~ name);
            static if (is(typeof(method) Return == return) && is(typeof(method) Arguments == __parameters))
            {
                uint[Arguments.length] modes;
                static foreach (parameter; 0 .. Arguments.length)
                {
                    {
                        enum mode = storageFlags(__traits(getParameterStorageClasses, typeof(method), parameter));
                        static assert(mode == Storage.none || mode == Storage.ref_
                                || mode == Storage.in_, "mock parameters must be value, ref, or in");
                        modes[parameter] = mode;
                    }
                }
                sources[index] = methodSource(index, name, attributes, !is(Return == void), modes[]);
            }
        }
    }
    return joined(sources[]);
}

// One formatter shared by every mock instead of one per generated method.
private string missedCalls(string name, size_t expected, size_t observed)
{
    return name ~ " expected " ~ decimal(expected) ~ " call(s), received " ~ decimal(observed);
}

private struct Plan(alias method)
{
    static if (is(typeof(method) Return == return))
        alias Value = Return;
    static if (is(typeof(method) Arguments == __parameters))
        alias Params = Arguments;
    static if (!is(Value == void))
        Value[] values;
    size_t expected;
    size_t observed;
}

private string planList(size_t count) pure
{
    string source;
    foreach (index; 0 .. count)
        source ~= (index == 0 ? "Plan!(MethodList[" : ", Plan!(MethodList[") ~ decimal(index) ~ "])";
    return source;
}

package(flint.test) final class MockState(Contract)
{
    private alias MethodList = methodsOf!Contract;
    // A built-in field sequence, one plan per method; std.typecons.Tuple would instantiate its comparison,
    // hashing and formatting machinery for every mock.
    mixin("private alias Plans = Seq!(" ~ planList(MethodList.length) ~ ");");

    // Identifier and mangled type of each method, for overload lookups by `slotOf`.
    private enum string[MethodList.length] methodNames = () {
        string[MethodList.length] names;
        static foreach (index, method; MethodList)
            names[index] = __traits(identifier, method);
        return names;
    }();
    private enum string[MethodList.length] methodTypes = () {
        string[MethodList.length] types;
        static foreach (index, method; MethodList)
            types[index] = typeof(method).mangleof;
        return types;
    }();

    /// Plan slot of a method symbol or of an explicit `MockMethod` selection.
    template slotOf(alias selection)
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
        enum slotOf = findMethod(methodNames[], methodTypes[], __traits(identifier, method), typeof(method).mangleof);
        static assert(slotOf != size_t.max, "method is not in the mock interface");
    }

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
        alias Value = Plans[index].Value;
        static assert(!is(Value == void) && is(T : Value), "return value must match the mock method type");
        requireConfiguration();
        plans[index].values ~= result;
        ++plans[index].expected;
        ++expectedCount;
    }

    void configureVoid(size_t index)()
    {
        static assert(is(Plans[index].Value == void), "expects requires a void method");
        requireConfiguration();
        ++plans[index].expected;
        ++expectedCount;
    }

    Plans[index].Value invoke(size_t index)()
    {
        alias Value = Plans[index].Value;
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
            if (plans[index].observed < plans[index].expected)
                return missedCalls(__traits(identifier, method), plans[index].expected, plans[index].observed);
        }
        return null;
    }

    void reset()
    {
        static foreach (index; 0 .. Plans.length)
            plans[index] = Plans[index].init;
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
