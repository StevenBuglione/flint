module model_description_tests;

import flint.ai.model : ChatModelDescription, EmbeddingModelDescription;

@safe:

@("chat model descriptions inherit the empty description and version defaults")
unittest
{
    ChatModelDescription model = new TestChatDescription();
    assert(model.getName() == "test-chat");
    assert(model.getDescription() == "");
    assert(model.getVersion() == "");
}

@("embedding model descriptions combine the defaults and respect overrides")
unittest
{
    EmbeddingModelDescription model = new TestEmbeddingDescription();
    assert(model.getName() == "test-embeddings");
    assert(model.getDescription() == "Configured by the implementor");
    assert(model.getVersion() == "");
    assert(model.getDimensions() == -1);
}

private final class TestChatDescription : ChatModelDescription
{
    mixin ChatModelDescription.Defaults;

    override string getName()
    {
        return "test-chat";
    }
}

private final class TestEmbeddingDescription : EmbeddingModelDescription
{
    mixin EmbeddingModelDescription.Defaults;

    override string getName()
    {
        return "test-embeddings";
    }

    override string getDescription()
    {
        return "Configured by the implementor";
    }
}
