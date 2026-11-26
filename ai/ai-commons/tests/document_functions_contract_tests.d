module document_functions_contract_tests;

import flint.ai.document : Document, DocumentReader, DocumentTransformer, DocumentWriter;
import flint.engine.aot.any : Any;
import flint.java.util : List, Map;
import flint.java.util.function_ : Consumer, Function, Supplier;
import std.typecons : Nullable;

@safe:

private alias Documents = List!Document;

private Documents sampleDocuments(string id)
{
    auto document = new Document(id, Nullable!string("text"), Map!(string, Any).of());
    return Documents.of(document);
}

private class DefaultReader : DocumentReader
{
    mixin DocumentReader.Defaults;

    override Documents get()
    {
        return null;
    }
}

private final class FixtureReader : DefaultReader
{
    Documents supplied;

    override Documents get()
    {
        return supplied;
    }
}

private class DefaultWriter : DocumentWriter
{
    mixin DocumentWriter.Defaults;

    override void accept(Documents)
    {
        assert(false, "the default write must dispatch to the overridden accept");
    }
}

private final class FixtureWriter : DefaultWriter
{
    Documents received;

    override void accept(Documents documents)
    {
        received = documents;
    }
}

private class DefaultTransformer : DocumentTransformer
{
    mixin DocumentTransformer.Defaults;

    override Documents apply(Documents documents)
    {
        return documents;
    }
}

private final class FixtureTransformer : DefaultTransformer
{
    Documents received;
    Documents output;

    override Documents apply(Documents documents)
    {
        received = documents;
        return output;
    }
}

@("document readers implement Supplier and read uses virtual get")
unittest
{
    auto fixture = new FixtureReader();
    fixture.supplied = sampleDocuments("supplied");
    DocumentReader reader = fixture;
    Supplier!Documents supplier = reader;
    assert(reader.read() is fixture.supplied);
    assert(supplier.get() is fixture.supplied);
    assert(reader.read().get(0).getId() == "supplied");
}

@("document writers implement Consumer and write uses virtual accept")
unittest
{
    auto fixture = new FixtureWriter();
    DocumentWriter writer = fixture;
    Consumer!Documents consumer = writer;
    auto documents = sampleDocuments("written");
    writer.write(documents);
    assert(fixture.received is documents);
    auto another = sampleDocuments("also-written");
    consumer.accept(another);
    assert(fixture.received is another);
}

@("document transformers implement Function and transform uses virtual apply")
unittest
{
    auto fixture = new FixtureTransformer();
    fixture.output = sampleDocuments("output");
    DocumentTransformer transformer = fixture;
    Function!(Documents, Documents) operation = transformer;
    auto input = sampleDocuments("input");
    assert(transformer.transform(input) is fixture.output);
    assert(fixture.received is input);
    assert(operation.apply(input).get(0).getId() == "output");
}
