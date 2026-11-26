module app;

import flint.java.util.function_.longsupplier : LongSupplier;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    auto supplier = LongSupplier.of(() => value);
    auto operation = supplier.asDelegate();
    return cast(int)(operation() & 127);
}
