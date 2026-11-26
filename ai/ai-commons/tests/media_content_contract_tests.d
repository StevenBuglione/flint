module media_content_contract_tests;

import flint.ai.content : Content, Media, MediaContent;
import flint.ai.tokenizer : TokenCountEstimator;
import flint.engine.aot.any : Any;
import flint.java.lang : Iterable;
import flint.java.util : ArrayList, List, Map;
import std.typecons : Nullable;

@safe:

private final class FixtureMediaContent : MediaContent
{
    private Nullable!string text_;
    private Map!(string, Any) metadata_;
    private List!Media media_;

    this(Nullable!string text, Map!(string, Any) metadata, List!Media media)
    {
        text_ = text;
        metadata_ = metadata;
        media_ = media;
    }

    override Nullable!string getText()
    {
        return text_;
    }

    override Map!(string, Any) getMetadata()
    {
        return metadata_;
    }

    override List!Media getMedia()
    {
        return media_;
    }
}

@("media content retains its typed list and inherits the content contract")
unittest
{
    auto media = new ArrayList!Media();
    auto metadata = Map!(string, Any).of("source", Any.of("document"));
    MediaContent message = new FixtureMediaContent(Nullable!string("description"), metadata, media);
    Content content = message;
    assert(message.getMedia() is media && message.getMedia().isEmpty());
    assert(content.getText().get() == "description");
    assert(content.getMetadata() is metadata);
}

private final class FixtureTokenCountEstimator : TokenCountEstimator
{
    override int estimate(Nullable!string text)
    {
        return text.isNull ? -1 : cast(int) text.get().length;
    }

    override int estimate(MediaContent content)
    {
        return estimate(content.getText());
    }

    override int estimate(Iterable!MediaContent messages)
    {
        int total;
        foreach (MediaContent message; messages)
            total += estimate(message);
        return total;
    }
}

@("token count estimators dispatch nullable text and typed media content overloads")
unittest
{
    TokenCountEstimator estimator = new FixtureTokenCountEstimator();
    assert(estimator.estimate(Nullable!string.init) == -1);
    assert(estimator.estimate(Nullable!string("")) == 0);
    assert(estimator.estimate(Nullable!string("abcd")) == 4);

    auto media = List!Media.of();
    auto metadata = Map!(string, Any).of();
    MediaContent first = new FixtureMediaContent(Nullable!string("one"), metadata, media);
    MediaContent second = new FixtureMediaContent(Nullable!string("second"), metadata, media);
    Iterable!MediaContent messages = List!MediaContent.of(first, second);
    assert(estimator.estimate(first) == 3);
    assert(estimator.estimate(messages) == 9);
}
