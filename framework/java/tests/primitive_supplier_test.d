module flint.java.primitive_supplier_test;

import flint.java.util.function_ : FacadeIntSupplier = IntSupplier, FacadeLongSupplier = LongSupplier;
import flint.java.util.function_.intsupplier : IntSupplier;
import flint.java.util.function_.longsupplier : LongSupplier;

@safe:

unittest
{
    static assert(is(FacadeIntSupplier == IntSupplier));
    static assert(is(FacadeLongSupplier == LongSupplier));

    int integer = int.min;
    auto ints = IntSupplier.of(() => integer);
    auto readInt = ints.asDelegate();
    assert(readInt() == int.min);
    integer = -7;
    assert(ints.getAsInt() == -7 && readInt() == -7);

    long wide = (1L << 40) + 13;
    auto longs = LongSupplier.of(() => wide);
    auto readLong = longs.asDelegate();
    assert(readLong() == (1L << 40) + 13);
    wide = long.min;
    assert(longs.getAsLong() == long.min && readLong() == long.min);
}
