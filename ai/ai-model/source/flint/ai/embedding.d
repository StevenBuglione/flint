/*
 * Copyright 2023-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/embedding/{DefaultEmbeddingOptions,DefaultEmbeddingOptionsBuilder,Embedding,EmbeddingOptions,EmbeddingRequest,EmbeddingResultMetadata}.java
// Modified by the Flint authors.
module flint.ai.embedding;

import flint.ai.model : ModelOptions, ModelRequest, ModelResult, ResultMetadata;
import flint.engine.aot.any : Any;
import flint.java.lang : JavaObject;
import flint.java.util : List;
import flint.util : MimeType;
import std.typecons : Nullable;

@safe:

private alias ModelName = Nullable!string;
private alias Dimensions = Nullable!int;

/// The vector generated for one embedding input.
class Embedding : ModelResult!(float[])
{
    private float[] embedding_;
    private Nullable!int index_;
    private EmbeddingResultMetadata metadata_;

    /// Keeps the supplied vector, index and metadata.
    this(float[] embedding, Nullable!int index, EmbeddingResultMetadata metadata) pure nothrow @nogc
    {
        embedding_ = embedding;
        index_ = index;
        metadata_ = metadata;
    }

    /// Keeps the supplied vector and metadata with a present index.
    this(float[] embedding, int index, EmbeddingResultMetadata metadata) pure nothrow @nogc
    {
        this(embedding, Nullable!int(index), metadata);
    }

    /// Returns the supplied embedding vector.
    override float[] getOutput()
    {
        return embedding_;
    }

    /// Returns the index of the embedding, if present.
    Nullable!int getIndex()
    {
        return index_;
    }

    /// Returns the supplied metadata.
    override EmbeddingResultMetadata getMetadata()
    {
        return metadata_;
    }

    /// Compares vectors and indices for objects of the same concrete class.
    bool equals(Object other) pure nothrow @nogc
    {
        auto that = cast(Embedding) other;
        if (this is that)
            return true;
        if (that is null || typeid(this) !is typeid(that) || index_.isNull != that.index_.isNull)
            return false;
        return (index_.isNull || index_.get() == that.index_.get()) && sameVector(embedding_, that.embedding_);
    }

    /// Computes the Java hash of the vector and optional index.
    int hashCode() const pure nothrow @nogc
    {
        uint vectorHash;
        if (embedding_ !is null)
        {
            vectorHash = 1;
            foreach (value; embedding_)
                vectorHash = 31 * vectorHash + vectorBits(value);
        }

        const indexHash = index_.isNull ? 0U : cast(uint) index_.get();
        return cast(int)(31 * (31 + vectorHash) + indexHash);
    }

    /// Describes the result without rendering the vector elements.
    override string toString() const
    {
        import flint.ai.chat.messages.part : joinRecord;
        import flint.java.lang : Integer, NullPointerException;

        if (embedding_ is null)
            throw new NullPointerException();
        string[5] parts = [
            "Embedding{embedding=", embedding_.length == 0 ? "<empty>" : "<has data>", ", index=",
            index_.isNull ? "null" : Integer.toString(index_.get()), "}"
        ];
        return joinRecord(parts[]);
    }

    mixin JavaObject;

    private static bool sameVector(scope const(float)[] left, scope const(float)[] right) pure nothrow @nogc
    {
        if (left is right)
            return true;
        if (left is null || right is null || left.length != right.length)
            return false;
        foreach (i, value; left)
            if (vectorBits(value) != vectorBits(right[i]))
                return false;
        return true;
    }

    private static uint vectorBits(float value) pure nothrow @nogc
    {
        union Bits
        {
            float number;
            uint pattern;
        }

        Bits bits = void;
        bits.number = value;
        // Float.floatToIntBits preserves signed zero and gives every NaN the same bits.
        return (bits.pattern & 0x7fff_ffffU) > 0x7f80_0000U ? 0x7fc0_0000U : bits.pattern;
    }
}

/// Selects the model and dimensions of an embedding request.
interface EmbeddingOptions : ModelOptions
{
    /// The requested model, if set.
    ModelName getModel();

    /// The requested number of dimensions, if set.
    Dimensions getDimensions();

    /// Starts a builder with both settings absent.
    static Builder builder()
    {
        return new DefaultEmbeddingOptionsBuilder();
    }

    /// Sets the options for subsequent builds.
    interface Builder
    {
        /// Sets the model or clears it with null.
        Builder model(string model);

        /// Sets the number of dimensions.
        Builder dimensions(int dimensions);

        /// Sets or clears the number of dimensions.
        Builder dimensions(Dimensions dimensions);

        /// Builds an options instance from the current settings.
        EmbeddingOptions build();
    }
}

/// An embedding options snapshot.
class DefaultEmbeddingOptions : EmbeddingOptions
{
    private ModelName model_;
    private Dimensions dimensions_;

    /// Stores the selected model and dimensions.
    protected this(ModelName model, Dimensions dimensions) pure nothrow @nogc
    {
        import flint.ai.chat.messages.part : normalizeText;

        model_ = normalizeText(model);
        dimensions_ = dimensions;
    }

    /// Starts a builder for a default options snapshot.
    static Builder builder()
    {
        return new Builder();
    }

    /// The requested model, if set.
    override ModelName getModel()
    {
        return model_;
    }

    /// The requested number of dimensions, if set.
    override Dimensions getDimensions()
    {
        return dimensions_;
    }

    /// Builds separate default options instances from its settings.
    static final class Builder : EmbeddingOptions.Builder
    {
        private ModelName model_;
        private Dimensions dimensions_;

        private this()
        {
        }

        /// Sets the model or clears it with null.
        override Builder model(string model) pure nothrow @nogc
        {
            return this.model(model is null ? ModelName.init : ModelName(model));
        }

        /// Sets or clears the model.
        Builder model(ModelName model) pure nothrow @nogc
        {
            model_ = model;
            return this;
        }

        /// Sets the number of dimensions.
        override Builder dimensions(int dimensions) pure nothrow @nogc
        {
            return this.dimensions(Dimensions(dimensions));
        }

        /// Sets or clears the number of dimensions.
        override Builder dimensions(Dimensions dimensions) pure nothrow @nogc
        {
            dimensions_ = dimensions;
            return this;
        }

        /// Builds a snapshot whose settings survive later changes to this builder.
        override DefaultEmbeddingOptions build()
        {
            return new DefaultEmbeddingOptions(model_, dimensions_);
        }
    }
}

/// Default implementation of the embedding options builder interface.
class DefaultEmbeddingOptionsBuilder : EmbeddingOptions.Builder
{
    private DefaultEmbeddingOptions.Builder builder_;

    /// Starts a builder with both settings absent.
    this()
    {
        builder_ = DefaultEmbeddingOptions.builder();
    }

    /// Sets the model or clears it with null.
    override EmbeddingOptions.Builder model(string model)
    {
        builder_.model(model);
        return this;
    }

    /// Sets the number of dimensions.
    override EmbeddingOptions.Builder dimensions(int dimensions)
    {
        builder_.dimensions(dimensions);
        return this;
    }

    /// Sets or clears the number of dimensions.
    override EmbeddingOptions.Builder dimensions(Dimensions dimensions)
    {
        builder_.dimensions(dimensions);
        return this;
    }

    /// Builds an options instance from the current settings.
    override EmbeddingOptions build()
    {
        return builder_.build();
    }
}

/// A request to embed a list of input texts.
class EmbeddingRequest : ModelRequest!(List!string)
{
    private List!string inputs_;
    private EmbeddingOptions options_;

    /// Keeps the supplied inputs and options. Null options select model defaults.
    this(List!string inputs, EmbeddingOptions options) pure nothrow @nogc
    {
        inputs_ = inputs;
        options_ = options;
    }

    /// Returns the original list of inputs.
    override List!string getInstructions()
    {
        return inputs_;
    }

    /// Returns the supplied options, if present.
    override EmbeddingOptions getOptions()
    {
        return options_;
    }
}

/// Metadata about the source document of an embedding.
class EmbeddingResultMetadata : ResultMetadata
{
    private ModalityType modalityType_;
    private string documentId_;
    private MimeType mimeType_;
    private Any documentData_;

    /// The modality of the source document.
    enum ModalityType
    {
        /// Text.
        TEXT,
        /// Image.
        IMAGE,
        /// Audio.
        AUDIO,
        /// Video.
        VIDEO
    }

    /// Infers the modality of the source document from its MIME type.
    static class ModalityUtils
    {
        private static immutable MimeType imageType = MimeType.literal("image", "*");
        private static immutable MimeType audioType = MimeType.literal("audio", "*");
        private static immutable MimeType videoType = MimeType.literal("video", "*");
        private static immutable MimeType textType = MimeType.literal("text", "*");

        /// Checks the supported MIME families in Spring AI's order.
        static ModalityType getModalityType(MimeType mimeType)
        {
            import flint.ai.chat.messages.part : joinRecord;
            import flint.java.lang : IllegalArgumentException;

            if (mimeType.isCompatibleWith(imageType))
                return ModalityType.IMAGE;
            if (mimeType.isCompatibleWith(audioType))
                return ModalityType.AUDIO;
            if (mimeType.isCompatibleWith(videoType))
                return ModalityType.VIDEO;
            if (mimeType.isCompatibleWith(textType))
                return ModalityType.TEXT;

            string[2] message = ["Unsupported MimeType: ", mimeType.toString()];
            throw new IllegalArgumentException(joinRecord(message[]));
        }

        /// Returns the text modality when the MIME type is absent.
        static ModalityType getModalityType(Nullable!MimeType mimeType)
        {
            return mimeType.isNull ? ModalityType.TEXT : getModalityType(mimeType.get());
        }
    }

    /// Creates metadata for a plain text source with an empty document ID.
    this()
    {
        import flint.util : MimeTypeUtils;

        this("", ModalityType.TEXT, MimeTypeUtils.TEXT_PLAIN, Any.init);
    }

    /// Creates metadata for the supplied source document.
    this(string documentId, ModalityType modalityType, MimeType mimeType, Any documentData) pure nothrow @nogc
    {
        documentId_ = documentId;
        modalityType_ = modalityType;
        mimeType_ = mimeType;
        documentData_ = documentData;
    }

    /// Rejects an absent modality or MIME type.
    this(string documentId, Nullable!ModalityType modalityType, Nullable!MimeType mimeType, Any documentData)
    {
        import flint.java.lang : IllegalArgumentException;

        if (modalityType.isNull)
            throw new IllegalArgumentException("ModalityType must not be null");
        if (mimeType.isNull)
            throw new IllegalArgumentException("MimeType must not be null");
        this(documentId, modalityType.get(), mimeType.get(), documentData);
    }

    /// Returns the source modality.
    ModalityType getModalityType()
    {
        return modalityType_;
    }

    /// Returns the source MIME type.
    MimeType getMimeType()
    {
        return mimeType_;
    }

    /// Returns the source document ID.
    string getDocumentId()
    {
        return documentId_;
    }

    /// Returns the supplied document data, if present.
    Any getDocumentData()
    {
        return documentData_;
    }
}
