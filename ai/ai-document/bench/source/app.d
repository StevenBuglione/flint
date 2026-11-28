module app;

import core.stdc.stdio : fputc, stdout;
import flint.ai.document : Document;
import flint.engine.aot.any : Any;
import flint.java.util : Map;
import std.typecons : Nullable;

@safe:

private alias Text = Nullable!string;
private alias Metadata = Map!(string, Any);

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
    Document document = new Document(text, Metadata.of("source", Any.of(source)));

    emit(document.getId());
    emit(document.getText().isNull ? "[absent]" : document.getText().get());
    emit(document.getMetadata().get("source").get!string());
    return 0;
}
