module app;

import core.stdc.stdio : fputc, stdout;
import flint.engine.aot.any : Any;
import flint.java.util : Map;
import std.typecons : Nullable;

@safe:

private alias Text = Nullable!string;
private alias Metadata = Map!(string, Any);

private final class ExampleContent
{
    private Text text;
    private Metadata metadata;

    this(Text text, Metadata metadata)
    {
        this.text = text;
        this.metadata = metadata;
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
    const bool missing = args.length > 1 && args[1] == "--absent";
    const Text text = missing ? Text.init : Text(args.length > 1 ? args[1] : "content");
    const string source = args.length > 2 ? args[2] : "application";
    ExampleContent content = new ExampleContent(text, Metadata.of("source", Any.of(source)));
    const Text visible = content.getText();

    emit(visible.isNull ? "[absent]" : visible.get());
    emit(content.getMetadata().get("source").get!string());
    return 0;
}
