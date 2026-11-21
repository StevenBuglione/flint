module betterc_validate;
import flint.validate : Min, Max, Violation, validate;

@safe:
/// Both success and failing validation are observable.
struct Value
{
    /// Small range with explicit success and failure fixtures.
    @Min(1) @Max(9) int n;
}

private int behaviorTest() nothrow @nogc
{
    Violation[2] violations;
    Value value = Value(4);
    assert(validate(value, violations[]).valid);
    value.n = 10;
    const result = validate(value, violations[]);
    assert(!result.valid && result.total == 1 && result.written == 1);
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
