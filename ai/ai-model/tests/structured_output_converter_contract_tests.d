module structured_output_converter_contract_tests;

import flint.ai.converter : FormatProvider, StructuredOutputConverter;
import flint.core.convert.converter : Converter;

@safe:

@("structured output converters preserve conversion and format contracts")
unittest
{
    StructuredOutputConverter!int converter = new DefaultSchemaConverter();
    Converter!(string, int) conversion = converter;
    FormatProvider format = converter;

    assert(conversion.convert("hello") == 5);
    assert(format.getFormat() == "Return a word.");
    const schema = converter.getJsonSchema();
    assert(schema == StructuredOutputConverter!int.NO_JSON_SCHEMA && schema !is null);
}

@("structured output converters can override the default schema")
unittest
{
    StructuredOutputConverter!int converter = new WithSchemaConverter();
    assert(converter.getJsonSchema() == `{"type":"integer"}`);
}

private class DefaultSchemaConverter : StructuredOutputConverter!int
{
    mixin StructuredOutputConverter!int.Defaults;

    override int convert(string source)
    {
        return cast(int) source.length;
    }

    override string getFormat()
    {
        return "Return a word.";
    }
}

private final class WithSchemaConverter : DefaultSchemaConverter
{
    override string getJsonSchema()
    {
        return `{"type":"integer"}`;
    }
}
