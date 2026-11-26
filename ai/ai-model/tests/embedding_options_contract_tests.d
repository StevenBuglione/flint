module embedding_options_contract_tests;

import flint.ai.embedding : DefaultEmbeddingOptions, EmbeddingOptions, EmbeddingRequest;
import flint.ai.model : ModelOptions, ModelRequest;
import flint.java.util : ArrayList, List;
import std.typecons : Nullable;

@safe:

@("embedding requests retain the caller's instructions and optional options")
unittest
{
    List!string inputs = new ArrayList!string(["first"]);
    auto options = EmbeddingOptions.builder().model("test-embedding").build();
    auto configured = new EmbeddingRequest(inputs, options);
    ModelRequest!(List!string) request = configured;

    const EmbeddingOptions selected = configured.getOptions();
    assert(selected is options && request.getOptions() is options);
    assert(request.getInstructions() is inputs);
    inputs.add("second");
    assert(request.getInstructions().get(1) == "second");

    ModelRequest!(List!string) defaults = new EmbeddingRequest(inputs, null);
    assert(defaults.getOptions() is null && defaults.getInstructions() is inputs);
}

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
