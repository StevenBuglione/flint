module betterc_validate;
import flint.arena : RequestArena, Status, Text;
import flint.validate : Email, Max, Min, NotBlank, Pattern, Size, Valid, Violation, validate, validateIn;

@safe:
/// Both success and failing validation are observable.
struct Value
{
    /// Small range with explicit success and failure fixtures.
    @Min(1) @Max(9) int n;
}

private void numericBehavior() nothrow @nogc
{
    Violation[2] violations;
    Value value = Value(4);
    assert(validate(value, violations[]).valid);
    value.n = 10;
    const result = validate(value, violations[]);
    assert(!result.valid && result.total == 1 && result.written == 1);
    assert(violations[0].constraint[0] == 'M');
}

private struct Row
{
    @Pattern(r"^([ab]+)+\d$") @NotBlank Text caption;
    @Size(2, 2) string glyphs;
    @Email string contact;
    @Min(16_777_217) float amount;
}

private struct Form
{
    @Valid Row[2] rows;
}

private void textBehavior() nothrow @nogc
{
    ubyte[64] bytes;
    ubyte[64] unrelated;
    scope arena = RequestArena(bytes[]);
    scope other = RequestArena(unrelated[]);
    const stored = arena.copyIn(cast(const(ubyte)[]) "abba7");
    const blank = arena.copyIn(cast(const(ubyte)[]) "\u00A0\u200A");
    assert(stored.ok() && blank.ok());

    Row valid = Row(Text(stored.value), "猫é", "a+tag@x.io", 16_777_218.0f);
    const Row invalid = Row(Text(blank.value), "\xED\xA0\x80", "a@-x.io", 16_777_216.0f);
    Form form = Form([valid, valid]);
    Violation[6] output;
    assert(validateIn(form, arena, output[]).valid);
    assert(validateIn(form, other, []).total == 4);

    form.rows[1] = invalid;
    const small = validateIn(form, arena, output[0 .. 1]);
    assert(!small.valid && small.total == 5 && small.written == 1);
    assert(output[0].indexes[0] == 1 && output[0].indexCount == 1);
    assert(output[0].field.length == "rows[].caption".length);
    assert(output[0].constraint[0] == 'P');

    assert(arena.reset() == Status.ok);
    const stale = validateIn(form, arena, output[]);
    assert(stale.total == 7 && stale.written == 6);
}

private int behaviorTest() nothrow @nogc
{
    numericBehavior();
    textBehavior();
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
