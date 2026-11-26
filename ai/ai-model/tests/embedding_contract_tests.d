module embedding_contract_tests;

import flint.ai.embedding : Embedding, EmbeddingResultMetadata;
import flint.ai.model : ModelResult;
import flint.java.lang : NullPointerException;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

@("embedding results retain their vector and supplied metadata")
unittest
{
    float[] vector = [1.0f, 2.0f];
    auto metadata = new EmbeddingResultMetadata();
    auto embedding = new Embedding(vector, -4, metadata);
    ModelResult!(float[]) result = embedding;

    const EmbeddingResultMetadata supplied = embedding.getMetadata();
    assert(supplied is metadata && result.getMetadata() is metadata);
    assert(result.getOutput() is vector && embedding.getIndex().get() == -4);
    vector[0] = 3.0f;
    assert(result.getOutput()[0] == 3.0f);
    assert(embedding.toString() == "Embedding{embedding=<has data>, index=-4}");
}

@("embedding equality canonicalizes NaNs and distinguishes signed zeros")
unittest
{
    auto left = new Embedding([float.nan, 0.0f], 0, new EmbeddingResultMetadata());
    auto equal = new Embedding([-float.nan, 0.0f], 0, null);
    auto signedZero = new Embedding([float.nan, -0.0f], 0, null);
    auto absentIndex = new Embedding([float.nan, 0.0f], Nullable!int.init, null);
    assert(left.equals(equal) && left == equal && left.hashCode() == equal.hashCode());
    assert(!left.equals(signedZero) && left.hashCode() != signedZero.hashCode());
    assert(!left.equals(absentIndex));

    static class DerivedEmbedding : Embedding
    {
        this(float[] vector)
        {
            super(vector, 0, null);
        }
    }

    assert(!left.equals(new DerivedEmbedding([float.nan, 0.0f])));
}

@("null and empty embedding vectors have distinct Java hashes")
unittest
{
    float[] storage = [0.0f];
    auto empty = new Embedding(storage[0 .. 0], Nullable!int.init, null);
    auto absent = new Embedding(null, Nullable!int.init, null);
    assert(empty.getOutput() !is null && empty.getOutput().length == 0);
    assert(!empty.equals(absent) && absent.getOutput() is null);
    assert(empty.hashCode() == 992 && absent.hashCode() == 961);
    assert(empty.toString() == "Embedding{embedding=<empty>, index=null}");
    assertThrown!NullPointerException(absent.toString());
}
