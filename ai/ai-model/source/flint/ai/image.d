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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/image/{Image,ImageGeneration,ImageGenerationMetadata,ImageOptions,ImageOptionsBuilder}.java
// Modified by the Flint authors.
module flint.ai.image;

import flint.ai.model : ModelOptions, ModelResult, ResultMetadata;
import flint.java.lang : JavaObject;
import std.typecons : Nullable;

@safe:

private alias Text = Nullable!string;
private alias Count = Nullable!int;

/// An image represented by a URL or base64-encoded data.
class Image
{
    private Text url_;
    private Text b64Json_;

    /// Creates an image with either or both forms present.
    this(Text url, Text b64Json) pure nothrow @nogc
    {
        import flint.ai.chat.messages.part : normalizeText;

        url_ = normalizeText(url);
        b64Json_ = normalizeText(b64Json);
    }

    /// Returns the URL if present.
    Text getUrl() const pure nothrow @nogc
    {
        return url_;
    }

    /// Updates the URL.
    void setUrl(string url) pure nothrow @nogc
    {
        url_ = optionalText(url);
    }

    /// Returns the base64 data if present.
    Text getB64Json() const pure nothrow @nogc
    {
        return b64Json_;
    }

    /// Updates the base64 data.
    void setB64Json(string b64Json) pure nothrow @nogc
    {
        b64Json_ = optionalText(b64Json);
    }

    /// Compares the URL and base64 data.
    bool equals(Object other)
    {
        import flint.ai.chat.messages.part : sameText;

        auto that = cast(Image) other;
        return this is that || (that !is null && sameText(url_, that.url_) && sameText(b64Json_, that.b64Json_));
    }

    /// Computes the Java hash over the two image fields.
    int hashCode()
    {
        import flint.ai.chat.messages.part : textHash;

        return 31 * (31 + textHash(url_)) + textHash(b64Json_);
    }

    /// Returns the image's two fields in Java's display format.
    override string toString()
    {
        import flint.ai.chat.messages.part : joinRecord, recordText;

        string[5] parts = [
            "Image{url='", recordText(url_), "', b64Json='", recordText(b64Json_), "'}"
        ];
        return joinRecord(parts[]);
    }

    mixin JavaObject;
}

/// Metadata associated with the generation of an image.
interface ImageGenerationMetadata : ResultMetadata
{
}

private final class DefaultImageGenerationMetadata : ImageGenerationMetadata
{
}

/// A generated image and its associated metadata.
class ImageGeneration : ModelResult!Image
{
    private Image image_;
    private ImageGenerationMetadata metadata_;

    /// Creates a generation with shared, empty metadata.
    this(Image image) nothrow @nogc
    {
        import flint.engine.aot.objects : statelessInstance;

        this(image, statelessInstance!DefaultImageGenerationMetadata());
    }

    /// Creates a generation with the supplied image and metadata.
    this(Image image, ImageGenerationMetadata metadata) pure nothrow @nogc
    {
        image_ = image;
        metadata_ = metadata;
    }

    /// Returns the original image.
    override Image getOutput()
    {
        return image_;
    }

    /// Returns the metadata associated with this image.
    override ImageGenerationMetadata getMetadata()
    {
        return metadata_;
    }

    /// Renders the metadata and image using their object representations.
    override string toString()
    {
        import flint.ai.chat.messages.part : joinRecord;
        import flint.engine.aot.objects : objectToString;

        string[5] parts = [
            "ImageGeneration{imageGenerationMetadata=", objectToString(cast(Object) metadata_),
            ", image=", objectToString(image_), "}"
        ];
        return joinRecord(parts[]);
    }
}

/// Common settings for image generation models.
interface ImageOptions : ModelOptions
{
    /// The number of images requested, if set.
    Count getN();

    /// The model to use, if set.
    Text getModel();

    /// The requested width, if set.
    Count getWidth();

    /// The requested height, if set.
    Count getHeight();

    /// The requested response format, if set.
    Text getResponseFormat();

    /// The requested style, if set.
    Text getStyle();
}

/// Builds a shared, mutable set of image options (R12).
struct ImageOptionsBuilder
{
    private DefaultImageOptions options_;

    @disable this();

    private this(DefaultImageOptions options)
    {
        options_ = options;
    }

    /// Starts with all options absent.
    static ImageOptionsBuilder builder()
    {
        return ImageOptionsBuilder(new DefaultImageOptions());
    }

    /// Sets the number of requested images.
    ref ImageOptionsBuilder n(int n) return pure nothrow @nogc
    {
        return this.n(Count(n));
    }

    /// Sets or clears the requested image count.
    ref ImageOptionsBuilder n(Count n) return pure nothrow @nogc
    {
        options_.n = n;
        return this;
    }

    /// Sets the model.
    ref ImageOptionsBuilder model(string model) return pure nothrow @nogc
    {
        options_.model = optionalText(model);
        return this;
    }

    /// Sets the response format.
    ref ImageOptionsBuilder responseFormat(string responseFormat) return pure nothrow @nogc
    {
        options_.responseFormat = optionalText(responseFormat);
        return this;
    }

    /// Sets the width.
    ref ImageOptionsBuilder width(int width) return pure nothrow @nogc
    {
        return this.width(Count(width));
    }

    /// Sets or clears the requested width.
    ref ImageOptionsBuilder width(Count width) return pure nothrow @nogc
    {
        options_.width = width;
        return this;
    }

    /// Sets the height.
    ref ImageOptionsBuilder height(int height) return pure nothrow @nogc
    {
        return this.height(Count(height));
    }

    /// Sets or clears the requested height.
    ref ImageOptionsBuilder height(Count height) return pure nothrow @nogc
    {
        options_.height = height;
        return this;
    }

    /// Sets the style.
    ref ImageOptionsBuilder style(string style) return pure nothrow @nogc
    {
        options_.style = optionalText(style);
        return this;
    }

    /// Returns the builder's options object. Later setter calls update that same object.
    ImageOptions build() pure nothrow @nogc
    {
        return options_;
    }
}

private final class DefaultImageOptions : ImageOptions
{
    Count n;
    Text model;
    Count width;
    Count height;
    Text responseFormat;
    Text style;

    override Count getN() pure nothrow @nogc
    {
        return n;
    }

    override Text getModel() pure nothrow @nogc
    {
        return model;
    }

    override Count getWidth() pure nothrow @nogc
    {
        return width;
    }

    override Count getHeight() pure nothrow @nogc
    {
        return height;
    }

    override Text getResponseFormat() pure nothrow @nogc
    {
        return responseFormat;
    }

    override Text getStyle() pure nothrow @nogc
    {
        return style;
    }
}

private Text optionalText(string value) pure nothrow @nogc
{
    return value is null ? Text.init : Text(value);
}
