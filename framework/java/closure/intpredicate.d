module app;

import flint.java.util.function_.intpredicate : IntPredicate;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto positive = IntPredicate.of((int candidate) => candidate + value > 0);
    auto test = positive.asDelegate();
    return test(value - 1) ? 1 : 0;
}
