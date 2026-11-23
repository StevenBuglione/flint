module flint.java.any_inline_test;

import flint.engine.aot.any : Any;
import flint.java.time : LocalDate;
import std.typecons : Nullable;

@safe:

unittest
{
    // Jackson's per-property values go inline in Any, with no Box allocated: a date and a Nullable!int.
    auto date = Any.of(LocalDate.of(2026, 11, 23));
    assert(date.box!LocalDate is null && date.get!LocalDate == LocalDate.of(2026, 11, 23));
    auto number = Any.of(Nullable!int(7));
    assert(number.box!(Nullable!int) is null && number.get!(Nullable!int).get == 7);
}
