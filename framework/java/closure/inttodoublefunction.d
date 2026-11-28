module app;

import flint.java.util.function_.inttodoublefunction : IntToDoubleFunction;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto scale = IntToDoubleFunction.of((int input) => input * 0.5 + value);
    auto apply = scale.asDelegate();
    return (cast(int) apply(value)) & 127;
}
