/// Contract checks for Thymeleaf 3.1.7.RELEASE ObjectUtils.
module flint.thymeleaf.object_utils_tests;

import flint.engine.aot.any : Any;
import flint.thymeleaf.util : ObjectUtils;
import std.typecons : Nullable;

@safe:

@("nullSafe returns the original reference or the fallback") unittest
{
    Object target = new Object();
    Object fallback = new Object();
    Object absent;
    assert(ObjectUtils.nullSafe(target, fallback) is target);
    assert(ObjectUtils.nullSafe(absent, fallback) is fallback);
    assert(ObjectUtils.nullSafe(null, fallback) is fallback);
    assert(ObjectUtils.nullSafe(absent, absent) is null);
}

@("nullSafe respects erased nulls and explicit nullable values") unittest
{
    auto fallback = Any.of(2);
    auto original = Any.of(0);
    assert(ObjectUtils.nullSafe(Any.init, fallback).get!int() == 2);
    assert(ObjectUtils.nullSafe(original, fallback).get!int() == 0);
    assert(ObjectUtils.nullSafe(Any.of(cast(Object) null), fallback).get!int() == 2);

    Nullable!int absent;
    const zero = Nullable!int(0);
    const replacement = Nullable!int(2);
    assert(ObjectUtils.nullSafe(absent, replacement).get() == 2);
    assert(ObjectUtils.nullSafe(zero, replacement).get() == 0);
    assert(ObjectUtils.nullSafe(absent, absent).isNull());
}

@("plain empty strings and slices are present values under R5") unittest
{
    const string defaultText;
    assert(ObjectUtils.nullSafe(defaultText, "fallback") == "");
    assert(ObjectUtils.nullSafe("", "fallback") == "");
    assert(ObjectUtils.nullSafe("original", "fallback") == "original");

    int[] empty;
    auto replacement = [1, 2];
    assert(ObjectUtils.nullSafe(empty, replacement).length == 0);
    assert(ObjectUtils.nullSafe(replacement, empty) is replacement);

    Nullable!string missing;
    const presentEmpty = Nullable!string("");
    const fallback = Nullable!string("fallback");
    assert(ObjectUtils.nullSafe(missing, fallback).get() == "fallback");
    assert(ObjectUtils.nullSafe(presentEmpty, fallback).get() == "");

    assert(ObjectUtils.nullSafe(0, 5) == 0);
}
