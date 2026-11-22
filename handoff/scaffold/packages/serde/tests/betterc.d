module betterc_serde;
import flint.arena : RequestArena, Status;
import flint.serde : decodeInto, encodeJson;

@safe:
/// Scalar JSON input and output exercise without druntime allocation.
struct Value
{
    /// Integer field exercised by both JSON decoding and encoding.
    int n;
}

private int behaviorTest() nothrow @nogc
{
    ubyte[1024] storage;
    scope arena = RequestArena(storage[]);
    Value value;
    auto error = decodeInto(cast(const(ubyte)[]) `{"n":42}`, value, arena);
    assert(error.code == Status.ok && value.n == 42);
    auto output = encodeJson(value, arena);
    assert(output.ok() && output.value.length() > 0);
    return 0;
}

version (WebAssembly)
{
    /// Execute the real package assertions from a freestanding wasm32 host.
    extern (C) export int flint_test() nothrow @nogc
    {
        return behaviorTest();
    }
}
else
{
    extern (C) int main() nothrow @nogc
    {
        return behaviorTest();
    }
}
