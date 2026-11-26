module flint.java.date_test;

import flint.java.lang : ArithmeticException, IllegalArgumentException;
import flint.java.time : Instant;
import flint.java.util : Date, HashSet;

@safe:

unittest
{
    // Epoch milliseconds, with the instant round-tripping through Date.from and toInstant.
    auto epoch = new Date(0);
    assert(epoch.getTime() == 0 && epoch.toString() == "Thu Jan 01 00:00:00 UTC 1970");
    auto date = new Date(1_795_445_460_123); // 2026-11-23T14:51:00.123Z, a Monday
    assert(date.toString() == "Mon Nov 23 14:51:00 UTC 2026");
    assert(date.toInstant() == Instant.ofEpochMilli(1_795_445_460_123));
    assert(Date.from(Instant.ofEpochMilli(1_795_445_460_123)) == date);
    assert(new Date(-1).toString() == "Wed Dec 31 23:59:59 UTC 1969");
    assert(new Date(951_782_400_000).toString() == "Tue Feb 29 00:00:00 UTC 2000"); // a leap day
}

@("Date.from floors fractions and checks the full signed millisecond range")
unittest
{
    assert(Date.from(Instant.ofEpochMilli(long.min)).getTime() == long.min);
    assert(Date.from(Instant.ofEpochMilli(long.max)).getTime() == long.max);
    assert(Date.from(Instant.ofEpochSecond(9_223_372_036_854_775, 807_999_999)).getTime() == long.max);
    assert(Date.from(Instant.ofEpochSecond(-1, 999_999_999)).getTime() == -1);

    foreach (instant; [
        Instant.ofEpochSecond(-9_223_372_036_854_776, 191_999_999),
        Instant.ofEpochSecond(9_223_372_036_854_775, 808_000_000)
    ])
    {
        try
        {
            Date.from(instant);
            assert(false, "Expected Date.from to reject a millisecond outside the signed range");
        }
        catch (IllegalArgumentException error)
        {
            assert(error.msg == "java.lang.ArithmeticException: long overflow");
            assert(cast(ArithmeticException) error.getCause() !is null);
        }
    }
}

unittest
{
    // equals, hashCode and compareTo follow the millisecond, as Java's Date; setTime and clone.
    auto a = new Date(1000);
    auto b = new Date(1000);
    auto c = new Date(2000);
    assert(a == b && a.equals(b) && a.hashCode() == b.hashCode() && a != c);
    assert(a.before(c) && c.after(a) && !a.before(b) && a.compareTo(c) < 0 && c.compareTo(a) > 0 && a < c);
    assert(new Date(-1).hashCode() == 0); // (int)(-1L ^ (-1L >>> 32))
    assert(new Date(0x1_0000_0001).hashCode() == 0);
    auto copy = c.clone();
    copy.setTime(3000);
    assert(c.getTime() == 2000 && copy.getTime() == 3000);
    auto set = new HashSet!Date;
    set.add(a);
    assert(set.contains(b) && !set.contains(c));
}

unittest
{
    // new Date() reads the wall clock to the millisecond.
    const before = Instant.now().toEpochMilli();
    auto now = new Date;
    assert(now.getTime() >= before && now.getTime() <= Instant.now().toEpochMilli());
}
