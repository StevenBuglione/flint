module app;

import core.stdc.stdio : fputc, stdout;
import flint.engine.aot.any : Any;
import flint.java.util : Map;
import std.typecons : Nullable;

@safe:

private alias Text = Nullable!string;
private alias Metadata = Map!(string, Any);

private final class ExampleDocument
{
    private string id;
    private Text text;
    private Metadata metadata;

    this(string id, Text text, Metadata metadata)
    {
        this.id = id;
        this.text = text;
        this.metadata = metadata;
    }

    string getId()
    {
        return id;
    }

    Text getText()
    {
        return text;
    }

    Metadata getMetadata()
    {
        return metadata;
    }
}

private void emit(scope const(char)[] text) nothrow @nogc
{
    foreach (character; text)
        fputc(character, stdout);
    fputc('\n', stdout);
}

int main(string[] args)
{
    const Text text = Text(args.length > 1 ? args[1] : "content");
    const string source = args.length > 2 ? args[2] : "application";
    ExampleDocument document = new ExampleDocument("00000000-0000-4000-8000-000000000000", text,
            Metadata.of("source", Any.of(source)));

    emit(document.getId());
    emit(document.getText().isNull ? "[absent]" : document.getText().get());
    emit(document.getMetadata().get("source").get!string());
    return 0;
}
