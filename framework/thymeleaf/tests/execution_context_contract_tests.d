/// Contract checks for Thymeleaf 3.1.7.RELEASE StandardExpressionExecutionContext.
module flint.thymeleaf.standard.expression.execution_context_contract_tests;

import flint.thymeleaf.standard.expression : StandardExpressionExecutionContext;

@safe:

private alias Mode = StandardExpressionExecutionContext;

@("execution contexts preserve the upstream flag combinations") unittest
{
    const modes = [
        Mode.NORMAL, Mode.RESTRICTED, Mode.RESTRICTED_FORBID_UNSAFE_EXP_RESULTS,
        Mode.RESTRICTED_WITH_NORMAL_LINK_PARAMETERS
    ];
    const bool[3][4] restrictions = [
        [false, false, false], [true, true, false], [true, true, true], [true, true, false]
    ];
    const links = [Mode.NORMAL, Mode.RESTRICTED, Mode.RESTRICTED, Mode.NORMAL];
    Mode[8] variants;
    foreach (index, mode; modes)
    {
        auto converted = mode.withTypeConversion();
        assert(mode != converted);
        assert(mode.withoutTypeConversion() == mode);
        assert(converted.withTypeConversion() == converted);
        assert(converted.withoutTypeConversion() == mode);
        variants[index * 2] = mode;
        variants[index * 2 + 1] = converted;
        foreach (convertedIndex, context; [mode, converted])
        {
            assert(context.getRestrictVariableAccess() == restrictions[index][0]);
            assert(context.getRestrictExternalAccess() == restrictions[index][1]);
            assert(context.getForbidUnsafeExpressionResults() == restrictions[index][2]);
            assert(context.getPerformTypeConversion() == (convertedIndex == 1));
            assert(context.forLinkParameters() == links[index]);
        }
    }

    foreach (index, first; variants)
        foreach (second; variants[index + 1 .. $])
            assert(first != second, "distinct Java constants must remain distinct by value");
}

@("execution-mode transitions are available to a non-allocating caller") unittest
{
    auto convert = (Mode mode) pure nothrow @nogc => mode.withTypeConversion().forLinkParameters();
    assert(convert(Mode.RESTRICTED_FORBID_UNSAFE_EXP_RESULTS) == Mode.RESTRICTED);
    assert(convert(Mode.RESTRICTED_WITH_NORMAL_LINK_PARAMETERS) == Mode.NORMAL);
}
