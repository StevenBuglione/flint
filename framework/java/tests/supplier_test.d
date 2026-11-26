module flint.java.supplier_test;

import flint.java.util.function_ : CompatibilitySupplier = Supplier;
import flint.java.util.function_.supplier : Supplier;

@safe:

static assert(is(CompatibilitySupplier!Object == Supplier!Object));

private final class FixedSupplier : Supplier!Object
{
    private Object value;

    this(Object value)
    {
        this.value = value;
    }

    Object get()
    {
        return value;
    }
}

unittest
{
    auto first = new Object;
    auto second = new Object;
    Supplier!Object nominal = new FixedSupplier(first);
    assert(nominal.get() is first);

    Object current = first;
    auto supplier = Supplier!Object.of(() => current);
    auto get = supplier.asDelegate();
    assert(supplier.get() is first);
    current = second;
    assert(get() is second);
    current = null;
    assert(supplier.get() is null);
    assert(get() is null);
}
