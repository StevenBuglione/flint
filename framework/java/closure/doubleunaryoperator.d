module app;

import flint.java.util.function_.doubleunaryoperator : DoubleUnaryOperator;

@safe:

int main(string[] args)
{
    const value = cast(double) args.length;
    auto halve = DoubleUnaryOperator.of((double candidate) => candidate / (value + 1));
    auto apply = halve.asDelegate();
    return cast(int) apply(value) & 127;
}
