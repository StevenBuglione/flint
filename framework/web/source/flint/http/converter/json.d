/++
`org.springframework.http.converter.json`: the Jackson JSON converter.

Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/main/java/org/springframework/http/converter/AbstractJacksonHttpMessageConverter.java,
spring-web/src/main/java/org/springframework/http/converter/json/JacksonJsonHttpMessageConverter.java and
ProblemDetailJacksonMixin.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook. The converter writes through
`flint.jackson.databind.ObjectMapper` with the value's descriptor (ADR-030 section 5). It registers Spring's
`ProblemDetailJacksonMixin` behaviour: `@JsonInclude(NON_EMPTY)` and the `properties` map as `@JsonAnyGetter`, after
the other properties, which Jackson 3 sorts by name (detail, instance, status, title, type).
+/
module flint.http.converter.json;

import flint.engine.aot.any : Any;
import flint.http : HttpInputMessage, HttpOutputMessage, MediaType, ProblemDetail;
import flint.http.converter : AbstractHttpMessageConverter, HttpMessageConversionException,
    HttpMessageNotReadableException, HttpMessageNotWritableException;
import flint.jackson.core : JacksonException, JsonGenerator;
import flint.jackson.core.json : OutputSink;
import flint.jackson.databind : JsonMapper, ObjectMapper;
import flint.jackson.databind.exc : InvalidDefinitionException;

@safe:

/// `JacksonJsonHttpMessageConverter`: `application/json` and `application/*+json` through Jackson.
class JacksonJsonHttpMessageConverter : AbstractHttpMessageConverter
{
    private ObjectMapper mapper;
    /// Spring's `problemDetailMediaTypes`: one list for every `ProblemDetail`, not one per response.
    private MediaType[] problemDetailMediaTypes;

    /// With a default mapper.
    this()
    {
        this(new JsonMapper);
    }

    /// With `mapper` (Spring Boot passes its auto-configured `JsonMapper`).
    this(ObjectMapper mapper)
    {
        super(MediaType.APPLICATION_JSON, MediaType("application", "*+json"));
        this.mapper = mapper;
        problemDetailMediaTypes = [MediaType.APPLICATION_PROBLEM_JSON];
    }

    /// `getMediaTypesForProblemDetail`: a `ProblemDetail` is written as `application/problem+json` (RFC 9457).
    override MediaType[] getSupportedMediaTypes(string typeName)
    {
        if (typeName == "flint.http.ProblemDetail")
            return problemDetailMediaTypes;
        return super.getSupportedMediaTypes(typeName);
    }

    alias getSupportedMediaTypes = AbstractHttpMessageConverter.getSupportedMediaTypes;

    /// The mapper.
    ObjectMapper getMapper() pure nothrow @nogc
    {
        return mapper;
    }

    /// A type the mapper has a descriptor for, `Any`, `ProblemDetail`, or a `java.util` collection or map, which
    /// Jackson writes element by element through the elements' own descriptors (a top-level
    /// `ResponseEntity<List<OwnerDto>>` needs no descriptor of `List!OwnerDto`).
    protected override bool supports(string typeName)
    {
        return typeName == "flint.engine.aot.any.Any" || typeName == "flint.http.ProblemDetail"
            || isJavaContainer(typeName) || mapper.descriptors().find(typeName) !is null;
    }

    private static bool isJavaContainer(string typeName) pure nothrow @nogc
    {
        enum prefix = "flint.java.util.";
        if (typeName.length <= prefix.length || typeName[0 .. prefix.length] != prefix)
            return false;
        const rest = typeName[prefix.length .. $];
        foreach (i, c; rest)
        {
            if (c != '!')
                continue;
            switch (rest[0 .. i])
            {
            case "Collection", "List", "ArrayList", "Set", "HashSet", "LinkedHashSet", "Map",
                    "HashMap", "LinkedHashMap":
                    return true;
            default:
                return false;
            }
        }
        return false;
    }

    /// `AbstractJacksonHttpMessageConverter.readJavaType`: the body through the mapper's descriptor of `typeName`.
    /// A type the mapper cannot handle is a conversion error (500); any other Jackson failure is unreadable input
    /// (400), with Jackson's original message.
    protected override Any readInternal(string typeName, HttpInputMessage inputMessage)
    {
        try
            return mapper.readValue(inputMessage.getBody(), typeName);
        catch (InvalidDefinitionException ex)
            throw new HttpMessageConversionException("Type definition error: " ~ ex.getType(), ex);
        catch (JacksonException ex)
            throw new HttpMessageNotReadableException("JSON parse error: " ~ ex.getOriginalMessage(), ex, inputMessage);
    }

    protected override void writeInternal(Any value, HttpOutputMessage outputMessage)
    {
        import flint.java.io : IOException;

        if (value.holds!ProblemDetail)
        {
            try
                writeProblemDetail(value.get!ProblemDetail, &outputMessage.writeBody);
            catch (IOException e)
                throw e;
            catch (Exception e)
                throw new HttpMessageNotWritableException("Could not write JSON: " ~ e.msg, e);
            return;
        }
        // Streamed into the response as Spring's converter does: the mapper's recycled generator hands each full
        // buffer to the body, so a write allocates nothing of its own. A failure mid-document can follow a
        // partial body, as in Spring; the response's own I/O failure passes through unwrapped.
        try
            mapper.writeValue(&outputMessage.writeBody, value);
        catch (IOException e)
            throw e;
        catch (Exception e)
            throw new HttpMessageNotWritableException("Could not write JSON: " ~ e.msg, e);
    }

    /++
    Flint's fast path: the bytes `writeInternal` streams for `value` (a `ProblemDetail` through the mixin, anything
    else through the mapper), to `sink`, with the mapper's exceptions unwrapped. The fast path writes a body the
    generic path would write with this converter, to a buffer of its own.
    +/
    package(flint) void writeTo(Any value, OutputSink sink)
    {
        if (value.holds!ProblemDetail)
            writeProblemDetail(value.get!ProblemDetail, sink);
        else
            mapper.writeValue(sink, value);
    }

    /// `ProblemDetailJacksonMixin`: `@JsonInclude(NON_EMPTY)`, Jackson 3's name order for the bean properties
    /// (detail, instance, status, title, type), then the `properties` map as `@JsonAnyGetter`. One generator from the
    /// mapper (its recycled one: the converter never keeps it) streams the whole object into the body, as Spring's
    /// converter serializes it, so escaping, numbers and each property's value are Jackson's.
    private void writeProblemDetail(ProblemDetail detail, OutputSink sink)
    {
        mapper.writeWith(sink, (JsonGenerator g) {
            g.writeStartObject();
            if (detail.getDetail().length != 0)
                g.writeStringProperty("detail", detail.getDetail());
            if (auto instance = detail.getInstance())
                if (instance.toString().length != 0)
                    g.writeStringProperty("instance", instance.toString());
            g.writeName("status");
            g.writeNumber(cast(long) detail.getStatus());
            if (detail.getTitle().length != 0)
                g.writeStringProperty("title", detail.getTitle());
            if (auto type = detail.getType())
                if (type.toString().length != 0)
                    g.writeStringProperty("type", type.toString());
            foreach (name; detail.getPropertyNames())
            {
                g.writeName(name);
                mapper.writeValue(g, detail.getProperty(name));
            }
            g.writeEndObject();
        });
    }
}
