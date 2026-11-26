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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/embedding/{DefaultEmbeddingOptions,DefaultEmbeddingOptionsBuilder,EmbeddingOptions,EmbeddingRequest,EmbeddingResultMetadata}.java
// Modified by the Flint authors.
module flint.ai.embedding;

import flint.ai.model : ModelOptions, ModelRequest, ResultMetadata;
import flint.engine.aot.any : Any;
import flint.java.util : List;
import flint.util : MimeType;
import std.typecons : Nullable;

@safe:

private alias ModelName = Nullable!string;
private alias Dimensions = Nullable!int;

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
