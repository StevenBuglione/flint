module flint.java.primitive_consumer_test;

import flint.java.util.function_ : FacadeDoubleConsumer = DoubleConsumer,
    FacadeIntConsumer = IntConsumer, FacadeLongConsumer = LongConsumer;
import flint.java.util.function_.doubleconsumer : DoubleConsumer;
import flint.java.util.function_.intconsumer : IntConsumer;
import flint.java.util.function_.longconsumer : LongConsumer;

@safe:

unittest
{
    static assert(is(FacadeIntConsumer == IntConsumer));

    int[] values;
    auto consumer = IntConsumer.of((int value) { values ~= value; });
    auto accept = consumer.asDelegate();
    consumer.accept(int.min);
    accept(int.max);
    assert(values == [int.min, int.max]);
}

unittest
{
    static assert(is(FacadeLongConsumer == LongConsumer));

    long[] values;
    auto consumer = LongConsumer.of((long value) { values ~= value; });
    auto accept = consumer.asDelegate();
    consumer.accept(long.min);
    accept(long.max);
    assert(values == [long.min, long.max]);
}

unittest
{
    static assert(is(FacadeDoubleConsumer == DoubleConsumer));

    static union Bits
    {
        double value;
        ulong raw;
    }

    ulong[] bits;
    auto consumer = DoubleConsumer.of((double value) { bits ~= Bits(value).raw; });
    auto accept = consumer.asDelegate();
    consumer.accept(-0.0);
    accept(double.nan);
    consumer.accept(-double.infinity);
    assert(bits == [0x8000_0000_0000_0000UL, 0x7FF8_0000_0000_0000UL, 0xFFF0_0000_0000_0000UL]);
}
