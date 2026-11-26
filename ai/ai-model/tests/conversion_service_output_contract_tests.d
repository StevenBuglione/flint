module conversion_service_output_contract_tests;

import flint.ai.converter : AbstractConversionServiceOutputConverter;
import flint.core.convert.support : DefaultConversionService;

@safe:

@("conversion service output converters retain the supplied service and schema default")
unittest
{
    auto service = new DefaultConversionService();
    AbstractConversionServiceOutputConverter!int converter = new NumberOutputConverter(service);
    assert(converter.getConversionService() is service);
    assert(converter.convert("42") == 42);
    assert(converter.getJsonSchema() == "");
}

private final class NumberOutputConverter : AbstractConversionServiceOutputConverter!int
{
    this(DefaultConversionService service)
    {
        super(service);
    }

    override int convert(string text)
    {
        return getConversionService().convert!int(text);
    }

    override string getFormat()
    {
        return "Return a number.";
    }
}
