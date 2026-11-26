module content_tests;

import flint.ai.content : Content;
import flint.engine.aot.any : Any;
import flint.java.util : Map;
import std.typecons : Nullable;

@safe:

private alias Metadata = Map!(string, Any);
private alias Text = Nullable!string;

private final class FixtureContent : Content
{
    private Text text;
    private Metadata metadata;

    this(Text text, Metadata metadata)
    {
        this.text = text;
        this.metadata = metadata;
    }

    override Text getText()
    {
        return text;
    }

    override Metadata getMetadata()
    {
        return metadata;
    }
}

@("content implementations expose missing and empty text with typed metadata")
unittest
{
    auto metadata = Metadata.of("source", Any.of("document"), "page", Any.of(7));
    Content missing = new FixtureContent(Text.init, metadata);
    Content blank = new FixtureContent(Text(""), metadata);
    assert(missing.getText().isNull);
    assert(!blank.getText().isNull && blank.getText().get() == "");
    assert(blank.getMetadata() is metadata);
    assert(missing.getMetadata().get("source").get!string() == "document");
    assert(missing.getMetadata().get("page").get!int() == 7);
}
