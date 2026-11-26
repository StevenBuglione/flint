module app;

import flint.java.util.function_ : BiFunction;

@safe:

int main(string[] args)
{
    const input = cast(int) args.length;
    auto combine = BiFunction!(int, int, int).of((int a, int b) => a + b);
    return combine.apply(input, 1) & 127;
}
