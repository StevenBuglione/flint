module image_contract_tests;

import flint.ai.image : Image, ImageGeneration, ImageGenerationMetadata, ImageOptions, ImageOptionsBuilder;
import flint.ai.model : ModelOptions, ModelResult;
import std.typecons : Nullable, nullable;

@safe:

@("image generations share default metadata and return their original image")
unittest
{
    auto image = new Image(nullable("https://example.invalid/image"), Nullable!string.init);
    auto first = new ImageGeneration(image);
    auto second = new ImageGeneration(image);
    ModelResult!Image result = first;
    assert(result.getOutput() is image);
    assert(first.getMetadata() !is null && first.getMetadata() is second.getMetadata());
    assert(result.getMetadata() is first.getMetadata());
}

@("image generations preserve supplied metadata and render its value")
unittest
{
    static final class ProviderMetadata : ImageGenerationMetadata
    {
        override string toString() const
        {
            return "provider metadata";
        }
    }

    auto image = new Image(Nullable!string.init, nullable("dGVzdA=="));
    auto metadata = new ProviderMetadata();
    auto generation = new ImageGeneration(image, metadata);
    const ImageGenerationMetadata typedMetadata = generation.getMetadata();
    ModelResult!Image result = generation;
    assert(typedMetadata is metadata && result.getMetadata() is metadata);
    enum prefix = "ImageGeneration{imageGenerationMetadata=provider metadata, ";
    assert(generation.toString() == prefix ~ "image=Image{url='null', b64Json='dGVzdA=='}}");
    assert(new ImageGeneration(null, null).toString() == "ImageGeneration{imageGenerationMetadata=null, image=null}");
}

@("images distinguish missing and empty fields in equality and rendering")
unittest
{
    alias Text = Nullable!string;
    auto absent = new Image(Text.init, Text.init);
    auto empty = new Image(Text.init, nullable(""));
    auto equal = new Image(Text.init, nullable(""));
    assert(absent.getUrl().isNull && absent.getB64Json().isNull);
    assert(empty.getB64Json().get() == "");
    assert(!absent.equals(empty));
    assert(empty == equal);
    assert(empty.hashCode() == equal.hashCode());
    assert(absent.toString() == "Image{url='null', b64Json='null'}");
    assert(empty.toString() == "Image{url='null', b64Json=''}");

    empty.setUrl("https://example.invalid/image");
    empty.setB64Json("dGVzdA==");
    assert(empty.getUrl().get() == "https://example.invalid/image");
    assert(empty.getB64Json().get() == "dGVzdA==");
    assert(empty.toString() == "Image{url='https://example.invalid/image', b64Json='dGVzdA=='}");
}

@("image option defaults are absent and fluent settings pass through")
unittest
{
    ImageOptions defaults = ImageOptionsBuilder.builder().build();
    assert(defaults.getN().isNull && defaults.getWidth().isNull && defaults.getHeight().isNull);
    assert(defaults.getModel().isNull && defaults.getResponseFormat().isNull && defaults.getStyle().isNull);

    ImageOptions options = ImageOptionsBuilder.builder().model("test-model").n(2).width(640)
        .height(480).responseFormat("b64_json").style("").build();
    const ModelOptions generic = options;
    assert(cast(const ImageOptions) generic is options);
    assert(options.getModel().get() == "test-model");
    assert(options.getN().get() == 2);
    assert(options.getWidth().get() == 640 && options.getHeight().get() == 480);
    assert(options.getResponseFormat().get() == "b64_json" && options.getStyle().get() == "");
}

@("image option builds and copies share one mutable options object")
unittest
{
    auto builder = ImageOptionsBuilder.builder();
    auto first = builder.model("old").build();
    auto aliasBuilder = builder;
    const second = aliasBuilder.model("new").width(0).build();
    assert(first is second);
    assert(first.getModel().get() == "new");
    assert(first.getWidth().get() == 0);
    aliasBuilder.width(Nullable!int.init);
    assert(first.getWidth().isNull);
    assert(ImageOptionsBuilder.builder().build().getModel().isNull);
}
