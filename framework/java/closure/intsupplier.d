module app;

import flint.java.util.function_.intsupplier : IntSupplier;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto supplier = IntSupplier.of(() => value);
    auto operation = supplier.asDelegate();
    return cast(int)(operation() & 127);
}
