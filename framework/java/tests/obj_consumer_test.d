module flint.java.obj_consumer_test;

import flint.java.util.function_ : FacadeObjDoubleConsumer = ObjDoubleConsumer,
    FacadeObjIntConsumer = ObjIntConsumer, FacadeObjLongConsumer = ObjLongConsumer;
import flint.java.util.function_.objdoubleconsumer : ObjDoubleConsumer;
import flint.java.util.function_.objintconsumer : ObjIntConsumer;
import flint.java.util.function_.objlongconsumer : ObjLongConsumer;

@safe:

unittest
{
    static assert(is(FacadeObjIntConsumer!string == ObjIntConsumer!string));

    long total;
    auto add = ObjIntConsumer!string.of((string text, int number) { total += number + text.length; });
    auto accept = add.asDelegate();
    add.accept("ab", 3);
    assert(total == 5);
    accept("xyz", 4);
    assert(total == 12);
}

unittest
{
    static assert(is(FacadeObjLongConsumer!string == ObjLongConsumer!string));

    long total;
    auto add = ObjLongConsumer!string.of((string text, long number) { total += number + text.length; });
    auto accept = add.asDelegate();
    add.accept("ab", 3);
    assert(total == 5);
    accept("xyz", 10);
    assert(total == 18);
}

unittest
{
    static assert(is(FacadeObjDoubleConsumer!string == ObjDoubleConsumer!string));

    double total = 0.0;
    auto add = ObjDoubleConsumer!string.of((string text, double number) {
        total += number + text.length;
    });
    auto accept = add.asDelegate();
    add.accept("ab", 0.5);
    assert(total == 2.5);
    accept("xyz", -1.5);
    assert(total == 4.0);
}
