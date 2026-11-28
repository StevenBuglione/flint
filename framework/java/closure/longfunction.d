module app;

import flint.java.util.function_.longfunction : LongFunction;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    auto addOne = LongFunction!long.of((long input) => input + 1);
    auto apply = addOne.asDelegate();
    return cast(int)(apply(value) & 127);
}
