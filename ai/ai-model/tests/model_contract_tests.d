module model_contract_tests;

import flint.ai.model : FlintAIModelProperties, FlintAIModels, ModelOptions, ModelRequest,
    ModelResult, ResultMetadata;

@safe:

@("model property keys use the Flint prefix and preserve nested options")
unittest
{
    static assert(!__traits(compiles, new FlintAIModelProperties()));
    assert(FlintAIModelProperties.MODEL_PREFIX == "flint.ai.model");
    assert(FlintAIModelProperties.EMBEDDING_MODEL == "flint.ai.model.embedding");
    assert(FlintAIModelProperties.TEXT_EMBEDDING_MODEL == "flint.ai.model.embedding.text");
    assert(FlintAIModelProperties.MULTI_MODAL_EMBEDDING_MODEL == "flint.ai.model.embedding.multimodal");
    assert(FlintAIModelProperties.AUDIO_TRANSCRIPTION_MODEL == "flint.ai.model.audio.transcription");
}

@("provider selectors preserve external identifiers")
unittest
{
    static assert(!__traits(compiles, new FlintAIModels()));
    assert(FlintAIModels.BEDROCK_CONVERSE == "bedrock-converse");
    assert(FlintAIModels.OPENAI_SDK == "openai-sdk");
    assert(FlintAIModels.STABILITY_AI == "stabilityai");
}

@("model requests expose typed instructions and optional model options")
unittest
{
    auto options = new TestOptions();
    ModelRequest!string configured = new TestRequest("Find the document", options);
    assert(configured.getInstructions() == "Find the document");
    assert(configured.getOptions() is options);

    ModelRequest!string defaults = new TestRequest("Use model defaults", null);
    assert(defaults.getInstructions() == "Use model defaults");
    assert(defaults.getOptions() is null);
}

@("model results expose typed output and its metadata")
unittest
{
    auto metadata = new TestMetadata();
    ModelResult!int result = new TestResult(42, metadata);
    assert(result.getOutput() == 42);
    assert(result.getMetadata() is metadata);
}

private final class TestOptions : ModelOptions
{
}

private final class TestRequest : ModelRequest!string
{
    private string instructions_;
    private ModelOptions options_;

    this(string instructions, ModelOptions options)
    {
        instructions_ = instructions;
        options_ = options;
    }

    override string getInstructions()
    {
        return instructions_;
    }

    override ModelOptions getOptions()
    {
        return options_;
    }
}

private final class TestMetadata : ResultMetadata
{
}

private final class TestResult : ModelResult!int
{
    private int output_;
    private ResultMetadata metadata_;

    this(int output, ResultMetadata metadata)
    {
        output_ = output;
        metadata_ = metadata;
    }

    override int getOutput()
    {
        return output_;
    }

    override ResultMetadata getMetadata()
    {
        return metadata_;
    }
}
