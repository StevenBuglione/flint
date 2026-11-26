module autoconfigure_tests.condition_outcome_test;

import flint.boot.autoconfigure.condition_runtime : ConditionMessage, ConditionOutcome;
import flint.java.lang : IllegalArgumentException;

@safe:

@("condition outcome preserves the supplied message and match flag")
unittest
{
    auto message = ConditionMessage.forCondition("@Feature").foundExactly("a bean");
    auto outcome = ConditionOutcome.match(message);
    assert(outcome.isMatch());
    assert(outcome.getConditionMessage() is message);
    assert(outcome.getMessage().get == "@Feature found a bean");
    assert(outcome.toString() == "@Feature found a bean");
    assert(!ConditionOutcome.noMatch("disabled").isMatch());
}

@("condition outcome Java overloads distinguish a missing string from a missing ConditionMessage")
unittest
{
    string missingText;
    ConditionMessage missingMessage;

    assert((new ConditionOutcome(true, missingText)).getMessage().isNull);
    assert(ConditionOutcome.match(missingText).getMessage().isNull);
    assert(ConditionOutcome.noMatch(missingText).getMessage().isNull);
    assert(ConditionOutcome.match().getMessage().isNull);
    assert(ConditionOutcome.noMatch("").getMessage().isNull);

    size_t rejected;
    try
        new ConditionOutcome(true, missingMessage);
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "'message' must not be null");
        ++rejected;
    }
    try
        ConditionOutcome.match(missingMessage);
    catch (IllegalArgumentException)
        ++rejected;
    try
        ConditionOutcome.noMatch(missingMessage);
    catch (IllegalArgumentException)
        ++rejected;
    assert(rejected == 3);
}

private final class CustomOutcome : ConditionOutcome
{
    this(bool matched, string message)
    {
        super(matched, message);
    }
}

@("condition outcome equality accounts for both content and the runtime class")
unittest
{
    auto match = ConditionOutcome.match("a feature");
    auto matchAgain = ConditionOutcome.match("a feature");
    auto miss = ConditionOutcome.noMatch("a feature");
    auto subclass = new CustomOutcome(true, "a feature");

    assert(match == matchAgain);
    assert(match.hashCode() == 1231 * 31 + match.getConditionMessage().hashCode());
    assert(matchAgain.hashCode() == match.hashCode());
    assert(miss.hashCode() == 1237 * 31 + miss.getConditionMessage().hashCode());
    assert(!match.equals(miss));
    assert(!match.equals(subclass) && !subclass.equals(match));
    assert(subclass.equals(new CustomOutcome(true, "a feature")));
}
