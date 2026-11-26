module model_contract_tests;

import flint.ai.model : ModelOptions, ModelRequest, ModelResult, ResultMetadata;

@safe:

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
