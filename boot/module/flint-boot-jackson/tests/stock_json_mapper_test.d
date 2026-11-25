// Flint's own tests for `stockJsonMapper` (Flint addition): the auto-configured JsonMapper when Jackson is configured
// as Boot leaves it, which the default-JSON-404 specialization requires of the converter's mapper.
module stock_json_mapper_test;

import flint.boot.jackson.autoconfigure : JacksonAutoConfiguration, JacksonProperties, JsonMapperBuilderCustomizer,
    stockJsonMapper;
import flint.context.support : GenericApplicationContext;
import flint.jackson.databind : JsonMapper;

@safe:

/// The beans JacksonAutoConfiguration defines, under its bean names, with `properties` (default when null).
private GenericApplicationContext jacksonContext(JacksonProperties properties = null,
        JsonMapperBuilderCustomizer extra = null, string mapperName = "jacksonJsonMapper")
{
    if (properties is null)
        properties = new JacksonProperties;
    auto configuration = new JacksonAutoConfiguration;
    auto customizer = configuration.standardJsonMapperBuilderCustomizer(properties);
    JsonMapperBuilderCustomizer[] customizers = [customizer];
    if (extra !is null)
        customizers ~= extra;
    auto builder = configuration.jsonMapperBuilder(customizers);
    auto context = new GenericApplicationContext;
    context.getBeanFactory().registerSingleton("jacksonProperties", properties);
    context.getBeanFactory().registerSingleton("standardJsonMapperBuilderCustomizer", customizer);
    if (extra !is null)
        context.getBeanFactory().registerSingleton("extraCustomizer", cast(Object) extra);
    context.getBeanFactory().registerSingleton("jsonMapperBuilder", builder);
    context.getBeanFactory().registerSingleton(mapperName, configuration.jacksonJsonMapper(builder));
    context.refresh();
    return context;
}

@("Boot's Jackson as it leaves it is stock: the auto-configured mapper") unittest
{
    auto context = jacksonContext();
    auto mapper = stockJsonMapper(context);
    assert(mapper !is null);
    assert(mapper is context.getBean("jacksonJsonMapper"));
}

@("any flint.jackson.* property refuses the proof") unittest
{
    auto indent = new JacksonProperties;
    indent.getSerialization().put("indent-output", true);
    assert(stockJsonMapper(jacksonContext(indent)) is null);
    auto dates = new JacksonProperties;
    dates.setDateFormat("yyyy-MM-dd");
    assert(stockJsonMapper(jacksonContext(dates)) is null);
    auto jackson2 = new JacksonProperties;
    jackson2.setUseJackson2Defaults(true);
    assert(stockJsonMapper(jacksonContext(jackson2)) is null);
    auto zone = new JacksonProperties;
    zone.setTimeZone("America/New_York");
    assert(stockJsonMapper(jacksonContext(zone)) is null);
}

private final class ExtraCustomizer : JsonMapperBuilderCustomizer
{
    void customize(JsonMapper.Builder builder)
    {
    }

    int getOrder() const pure nothrow @nogc
    {
        return 1;
    }
}

@("an application customizer or an application JsonMapper refuses the proof") unittest
{
    assert(stockJsonMapper(jacksonContext(null, new ExtraCustomizer)) is null);
    assert(stockJsonMapper(jacksonContext(null, null, "myMapper")) is null);
}
