module usage_tests;

import flint.ai.chat.metadata : Usage;
import flint.engine.aot.any : Any;
import std.typecons : Nullable;

@safe:

private alias TokenCount = Nullable!int;

@("usage defaults add token counts with missing counts treated as zero")
unittest
{
    Usage empty = new ProviderUsage(TokenCount.init, TokenCount.init);
    assert(empty.getPromptTokens().isNull);
    assert(empty.getCompletionTokens().isNull);
    assert(empty.getTotalTokens() == 0);
    assert(empty.getCacheReadInputTokens().isNull);
    assert(empty.getCacheWriteInputTokens().isNull);

    Usage partial = new ProviderUsage(TokenCount.init, TokenCount(7));
    assert(partial.getTotalTokens() == 7);
    Usage complete = new ProviderUsage(TokenCount(3), TokenCount(7));
    assert(complete.getTotalTokens() == 10);
}

@("usage totals wrap like Java integers")
unittest
{
    Usage positive = new ProviderUsage(TokenCount(int.max), TokenCount(1));
    assert(positive.getTotalTokens() == int.min);

    Usage negative = new ProviderUsage(TokenCount(int.min), TokenCount(-1));
    assert(negative.getTotalTokens() == int.max);
}

@("usage preserves missing and typed native provider values")
unittest
{
    Usage missing = new ProviderUsage(TokenCount(0), TokenCount.init);
    assert(!missing.getPromptTokens().isNull && missing.getPromptTokens().get() == 0);
    assert(missing.getNativeUsage().isNull());

    Usage present = new ProviderUsage(TokenCount(1), TokenCount(2), Any.of("provider data"));
    assert(present.getNativeUsage().get!string() == "provider data");
}

private final class ProviderUsage : Usage
{
    private TokenCount prompt_;
    private TokenCount completion_;
    private Any native_;

    this(TokenCount prompt, TokenCount completion, Any nativeUsage = Any.init)
    {
        prompt_ = prompt;
        completion_ = completion;
        native_ = nativeUsage;
    }

    mixin Usage.Defaults;

    override TokenCount getPromptTokens()
    {
        return prompt_;
    }

    override TokenCount getCompletionTokens()
    {
        return completion_;
    }

    override Any getNativeUsage()
    {
        return native_;
    }
}
