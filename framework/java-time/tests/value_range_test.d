module flint.java.time.value_range_test;

import core.memory : GC;
import flint.java.lang : IllegalArgumentException;
import flint.java.time.temporal.valuerange : ValueRange;

@safe:

@("fixed and variable ranges preserve the four bounds without allocating") unittest
{
    const before = GC.stats().allocatedInCurrentThread;
    const days = ValueRange.of(1, 28, 31);
    assert(days.getMinimum() == 1 && days.getLargestMinimum() == 1);
    assert(days.getSmallestMaximum() == 28 && days.getMaximum() == 31);
    assert(!days.isFixed() && days.isIntValue());
    assert(days.isValidIntValue(30) && days.isValidIntValue(31));
    assert(!days.isValidValue(0) && !days.isValidIntValue(32));

    const variable = ValueRange.of(-4, 6, 3, 12);
    assert(variable.isValidValue(-4) && variable.isValidValue(12));
    assert(variable.equals(ValueRange.of(-4, 6, 3, 12)));
    assert(!variable.equals(ValueRange.of(-4, 5, 3, 12)));
    const wide = ValueRange.of(long.min, long.max);
    assert(wide.isFixed() && wide.isValidValue(long.min) && wide.isValidValue(long.max));
    assert(!wide.isIntValue() && !wide.isValidIntValue(0));
    assert(ValueRange.of(int.min, int.max).isValidIntValue(int.min));
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("factories reject inconsistent lower and upper bounds") unittest
{
    void rejects(scope ValueRange delegate() @safe factory, string message)
    {
        try
        {
            factory();
            assert(false, "invalid range was accepted");
        }
        catch (IllegalArgumentException exception)
        {
            assert(exception.msg == message);
        }
    }

    rejects(() => ValueRange.of(2, 1), "Minimum value must be less than maximum value");
    rejects(() => ValueRange.of(1, 4, 3), "Smallest maximum value must be less than largest maximum value");
    rejects(() => ValueRange.of(4, 3, 5), "Minimum value must be less than smallest maximum value");
    rejects(() => ValueRange.of(3, 2, 4, 5), "Smallest minimum value must be less than largest minimum value");
    rejects(() => ValueRange.of(1, 5, 2, 4), "Largest minimum value must be less than largest maximum value");
    rejects(() => ValueRange.of(4, 5, 3, 6), "Smallest minimum value must be less than smallest maximum value");
}
