module embedding_options_contract_tests;

import flint.ai.embedding : DefaultEmbeddingOptions, EmbeddingOptions;
import flint.ai.model : ModelOptions;
import std.typecons : Nullable;

@safe:

@("embedding options build independent snapshots and preserve absent settings")
unittest
{
    EmbeddingOptions.Builder builder = EmbeddingOptions.builder();
    auto defaults = builder.build();
    assert(defaults.getModel().isNull && defaults.getDimensions().isNull);

    auto configured = builder.model("").dimensions(0).build();
    assert(configured !is defaults);
    assert(!configured.getModel().isNull && configured.getModel().get() == "");
    assert(!configured.getDimensions().isNull && configured.getDimensions().get() == 0);

    auto cleared = builder.model(null).dimensions(Nullable!int.init).build();
    assert(cleared.getModel().isNull && cleared.getDimensions().isNull);
    assert(defaults.getModel().isNull && defaults.getDimensions().isNull);
    assert(configured.getModel().get() == "" && configured.getDimensions().get() == 0);
}

@("the default embedding builder retains its concrete fluent build type")
unittest
{
    DefaultEmbeddingOptions.Builder builder = DefaultEmbeddingOptions.builder();
    DefaultEmbeddingOptions configured = builder.model("test-embedding").dimensions(24).build();
    const ModelOptions generic = configured;
    assert(cast(const EmbeddingOptions) generic is configured);

    DefaultEmbeddingOptions cleared = builder.model(Nullable!string.init).dimensions(Nullable!int.init).build();
    assert(cleared.getModel().isNull && cleared.getDimensions().isNull);
    assert(configured.getModel().get() == "test-embedding" && configured.getDimensions().get() == 24);
}
