/// Public expression-object contract checks for Thymeleaf 3.1.7.RELEASE.
module flint.thymeleaf.expression_objects_contract_tests;

import flint.engine.aot.any : Any;
import flint.java.util : LinkedHashSet, Set;
import flint.thymeleaf.expression : IExpressionObjects;

@safe:

private final class FixedObjects : IExpressionObjects
{
    enum string ordinary = "tool";
    enum string restricted = ordinary ~ IExpressionObjects.RESTRICTED_NAME_MODIFIER;

    private Set!string names;
    private Object marker;

    this(Object marker)
    {
        names = new LinkedHashSet!string();
        names.add(ordinary);
        names.add(restricted);
        this.marker = marker;
    }

    override int size()
    {
        return names.size();
    }

    override bool containsObject(string name)
    {
        return names.contains(name);
    }

    override Set!string getObjectNames()
    {
        return names;
    }

    override Any getObject(string name)
    {
        switch (name)
        {
        case ordinary:
            return Any.of(marker);
        case restricted:
            return Any.of(42);
        default:
            return Any.init;
        }
    }
}

@("expression objects expose registered names, values, and the restricted variant suffix") unittest
{
    auto marker = new Object();
    IExpressionObjects objects = new FixedObjects(marker);
    assert(IExpressionObjects.RESTRICTED_NAME_MODIFIER == "[restricted]");
    assert(objects.size() == 2);
    assert(objects.getObjectNames().toArray() == ["tool", "tool[restricted]"]);
    assert(objects.containsObject("tool") && objects.containsObject("tool[restricted]"));
    assert(objects.getObject("tool").get!Object() is marker);
    assert(objects.getObject("tool[restricted]").get!int() == 42);
    assert(!objects.containsObject("missing") && objects.getObject("missing").isNull());
}
