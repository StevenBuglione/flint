module app;

import flint.java.util.function_.longpredicate : LongPredicate;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    auto positive = LongPredicate.of((long candidate) => candidate + value > 0);
    auto test = positive.asDelegate();
    return test(value - 1) ? 1 : 0;
}
