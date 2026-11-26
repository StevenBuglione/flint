module processor_contract_tests;

import flint.thymeleaf.processor : AbstractProcessor, IProcessor;
import flint.thymeleaf.templatemode : TemplateMode;

@safe:

private final class Processor : AbstractProcessor
{
    this(TemplateMode mode, int precedence)
    {
        super(mode, precedence);
    }
}

private final class CustomProcessor : IProcessor
{
    TemplateMode getTemplateMode()
    {
        return TemplateMode.JAVASCRIPT;
    }

    int getPrecedence()
    {
        return 172;
    }
}

@("processor metadata is available through the interface") unittest
{
    IProcessor custom = new CustomProcessor();
    assert(custom.getTemplateMode() == TemplateMode.JAVASCRIPT && custom.getPrecedence() == 172);

    foreach (mode; TemplateMode.values())
    {
        foreach (precedence; [int.min, -1, 0, int.max])
        {
            IProcessor processor = new Processor(mode, precedence);
            assert(processor.getTemplateMode() == mode);
            assert(processor.getPrecedence() == precedence);
        }
    }
}

@("the base processor requires a TemplateMode value") unittest
{
    static assert(!__traits(compiles, {
            final class NullModeProcessor : AbstractProcessor
            {
                this()
                {
                    super(null, 1);
                }
            }

            new NullModeProcessor();
        }));
    assert((new Processor(TemplateMode.init, 1)).getTemplateMode() == TemplateMode.HTML);
}
