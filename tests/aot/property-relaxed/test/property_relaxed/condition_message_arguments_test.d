/// Verify the result arguments of Boot's condition-message builders.
module property_relaxed.condition_message_arguments_test;

import flint.boot.autoconfigure.condition_runtime : ConditionMessage;
import flint.engine.aot.any : Any;

@safe:

private final class DiagnosticValue
{
    override string toString() const
    {
        return "custom result";
    }
}

@("Condition message result builders preserve plain and erased argument text")
unittest
{
    auto builder = ConditionMessage.forCondition("Feature");
    assert(builder.foundExactly(17).toString() == "Feature found 17");
    assert(builder.foundExactly(Any.of(17)).toString() == "Feature found 17");
    assert(builder.resultedIn(true).toString() == "Feature resulted in true");
    assert(builder.resultedIn(Any.of(true)).toString() == "Feature resulted in true");

    auto value = new DiagnosticValue();
    assert(builder.foundExactly(value).toString() == "Feature found custom result");
    assert(builder.foundExactly(Any.of(value)).toString() == "Feature found custom result");
    assert(builder.resultedIn(value).toString() == "Feature resulted in custom result");
    assert(builder.resultedIn(Any.of(value)).toString() == "Feature resulted in custom result");
}

@("Condition message result builders handle erased null according to the clause")
unittest
{
    auto builder = ConditionMessage.forCondition("Feature");
    assert(builder.foundExactly(Any.init).toString() == "Feature found");
    assert(builder.resultedIn(Any.init).toString() == "Feature resulted in null");
}
