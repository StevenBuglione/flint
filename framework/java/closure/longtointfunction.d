module app;

import flint.java.util.function_.longtointfunction : LongToIntFunction;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    auto narrow = LongToIntFunction.of((long input) => cast(int) input + 1);
    auto apply = narrow.asDelegate();
    return (apply(value) & 127);
}
