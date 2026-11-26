/// Contract checks for Thymeleaf 3.1.7.RELEASE's #objects expression object.
module flint.thymeleaf.objects_expression_tests;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : ArrayList, LinkedHashSet, List, Set;
import flint.thymeleaf.expression : Objects;
import std.typecons : Nullable;

@safe:

@("the objects expression utility copies arrays and fills null values") unittest
{
    auto objects = new Objects();
    auto marker = new Object();
    auto fallback = new Object();
    auto values = [marker, null, fallback];
    auto updated = objects.arrayNullSafe(values, fallback);
    assert(updated !is values && updated == [marker, fallback, fallback]);
    assert(values[1] is null);
    updated[0] = fallback;
    assert(values[0] is marker);
    assert(objects.nullSafe(null, fallback) is fallback);

    Object[] empty;
    assert(objects.arrayNullSafe(empty, fallback).length == 0);

    auto boxed = [Any.init, Any.of(0)];
    auto replaced = objects.arrayNullSafe(boxed, Any.of(3));
    assert(replaced[0].get!int() == 3 && replaced[1].get!int() == 0);
    assert(boxed[0].isNull());

    auto numbers = [Nullable!int.init, Nullable!int(0)];
    auto present = objects.arrayNullSafe(numbers, Nullable!int(5));
    assert(present[0].get() == 5 && present[1].get() == 0);
}

@("list copies preserve order and do not change their input") unittest
{
    auto objects = new Objects();
    auto marker = new Object();
    auto fallback = new Object();
    List!Object values = new ArrayList!Object();
    values.add(marker);
    values.add(null);
    values.add(fallback);
    auto updated = objects.listNullSafe(values, fallback);
    assert(updated !is values && updated.toArray() == [marker, fallback, fallback]);
    assert(values.get(1) is null);
    updated.add(marker);
    assert(values.size() == 3 && updated.size() == 4);
}

@("set copies deduplicate substitutions in the first encountered order") unittest
{
    auto objects = new Objects();
    auto marker = new Object();
    auto fallback = new Object();
    Set!Object values = new LinkedHashSet!Object();
    values.add(null);
    values.add(marker);
    values.add(fallback);
    auto updated = objects.setNullSafe(values, fallback);
    assert(updated !is values && updated.toArray() == [fallback, marker]);
    assert(values.size() == 3 && values.contains(null));
    updated.remove(marker);
    assert(values.contains(marker) && !updated.contains(marker));
}

@("null list and set containers are rejected") unittest
{
    auto objects = new Objects();
    List!Object missingList;
    Set!Object missingSet;
    try
    {
        objects.listNullSafe(missingList, null);
        assert(0, "expected a null list to be rejected");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "Target cannot be null");
    }
    try
    {
        objects.setNullSafe(missingSet, null);
        assert(0, "expected a null set to be rejected");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "Target cannot be null");
    }
}
