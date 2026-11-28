module app;

import flint.java.util.function_.doublepredicate : DoublePredicate;

@safe:

int main(string[] args)
{
    const value = cast(double) args.length;
    auto positive = DoublePredicate.of((double candidate) => candidate + value > 0.5);
    auto test = positive.asDelegate();
    return test(value - 1) ? 1 : 0;
}
