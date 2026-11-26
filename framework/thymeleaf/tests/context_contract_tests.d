/// Public context contract checks for Thymeleaf 3.1.7.RELEASE.
module flint.thymeleaf.context_contract_tests;

import flint.engine.aot.any : Any;
import flint.java.util : LinkedHashSet, Locale, Set;
import flint.thymeleaf.context : IContext;

@safe:

private final class Marker
{
}

private final class FixedContext : IContext
{
    private Set!string variableNames;
    private Marker marker;

    this(Marker marker)
    {
        variableNames = new LinkedHashSet!string();
        variableNames.add("ready");
        variableNames.add("marker");
        variableNames.add("unset");
        this.marker = marker;
    }

    override Locale getLocale()
    {
        return Locale.CANADA;
    }

    override bool containsVariable(string name)
    {
        return variableNames.contains(name);
    }

    override Set!string getVariableNames()
    {
        return variableNames;
    }

    override Any getVariable(string name)
    {
        switch (name)
        {
        case "ready":
            return Any.of(true);
        case "marker":
            return Any.of(marker);
        default:
            return Any.init;
        }
    }
}

@("a public context exposes locale, names and dynamic values") unittest
{
    auto marker = new Marker();
    IContext context = new FixedContext(marker);
    assert(context.getLocale().getLanguage() == "en");
    assert(context.getLocale().getCountry() == "CA");
    assert(context.getVariableNames().toArray() == ["ready", "marker", "unset"]);
    assert(context.getVariable("ready").get!bool());
    assert(context.getVariable("marker").get!Marker() is marker);
    assert(context.containsVariable("unset"));
    assert(context.getVariable("unset").isNull());
    assert(!context.containsVariable("absent"));
    assert(context.getVariable("absent").isNull());
}
