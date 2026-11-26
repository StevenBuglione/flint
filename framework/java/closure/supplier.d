module app;

import flint.java.util.function_.supplier : Supplier;

@safe:

int main(string[] args)
{
    int value = cast(int) args.length;
    auto supplier = Supplier!int.of(() => value);
    auto get = supplier.asDelegate();
    return get() & 127;
}
