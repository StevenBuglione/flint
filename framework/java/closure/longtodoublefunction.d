module app;

import flint.java.util.function_.longtodoublefunction : LongToDoubleFunction;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    auto scale = LongToDoubleFunction.of((long input) => input * 0.25);
    auto apply = scale.asDelegate();
    return (cast(int) apply(value)) & 127;
}
