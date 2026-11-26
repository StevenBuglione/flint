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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/document/{ContentFormatter,DefaultContentFormatter,Document,DocumentMetadata,DocumentReader,DocumentTransformer,DocumentWriter,MetadataMode}.java
// Modified by the Flint authors.
module flint.ai.document;

import flint.ai.content : copyContentMetadata;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, JavaObject;
import flint.java.util : List, Map;
import flint.java.util.function_ : Consumer, Function, Supplier;
import std.typecons : Nullable;

@safe:

/// Which document metadata is included in formatted content.
enum MetadataMode
{
    ALL,
    EMBED,
    INFERENCE,
    NONE,
}

/// Common keys for document metadata.
struct DocumentMetadata
{
    /// Distance between a document embedding and a query vector.
    static immutable DocumentMetadata DISTANCE = DocumentMetadata(0);

    /// A reference to content stored outside the vector store.
    static immutable DocumentMetadata CONTENT_REF = DocumentMetadata(1);

    private struct Entry
    {
        string name;
        string key;
    }

    private static immutable Entry[2] entries = [
        Entry("DISTANCE", "distance"), Entry("CONTENT_REF", "content_ref")
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the constant's declared name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the metadata key.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].key;
    }

    /// Returns the metadata key as this constant's text.
    string toString() const pure nothrow @nogc
    {
        return value();
    }

    /// Returns a fresh array in declaration order.
    static DocumentMetadata[] values() pure nothrow
    {
        return [DISTANCE, CONTENT_REF];
    }

    /// Looks up a constant by its exact declared name.
    static DocumentMetadata valueOf(string name)
    {
        import flint.java.lang : IllegalArgumentException, NullPointerException;

        if (name is null)
            throw new NullPointerException("Name is null");
        foreach (i, ref entry; entries)
            if (entry.name == name)
                return DocumentMetadata(cast(int) i);
        throw new IllegalArgumentException("No enum constant flint.ai.document.DocumentMetadata." ~ name);
    }
}

private alias DocumentText = Nullable!string;
private alias DocumentMetadataMap = Map!(string, Any);

/// Converts document text and metadata into formatted content.
interface ContentFormatter
{
    /// Formats a document using the requested metadata mode.
    string format(Document document, MetadataMode mode);
}

private alias MetadataKeys = List!string;

/// Formats document text and metadata using configurable templates and exclusions.
final class DefaultContentFormatter : ContentFormatter
{
    private enum defaultMetadataTemplate = "{key}: {value}";
    private enum defaultTextTemplate = "{metadata_string}\n\n{content}";
    version (Windows)
        private enum defaultMetadataSeparator = "\r\n";
    else
        private enum defaultMetadataSeparator = "\n";

    private string metadataTemplate_;
    private string metadataSeparator_;
    private string textTemplate_;
    private MetadataKeys excludedInferenceMetadataKeys_;
    private MetadataKeys excludedEmbedMetadataKeys_;

    private this(ref Builder configuration)
    {
        // Copy the template values and keep the configured lists by reference.
        metadataTemplate_ = configuration.metadataTemplate;
        metadataSeparator_ = configuration.metadataSeparator;
        textTemplate_ = configuration.textTemplate;
        excludedInferenceMetadataKeys_ = configuration.excludedInferenceMetadataKeys;
        excludedEmbedMetadataKeys_ = configuration.excludedEmbedMetadataKeys;
    }

    /// Starts a new formatter configuration.
    static Builder builder()
    {
        import flint.java.util : ArrayList;

        return Builder(new ArrayList!string(), new ArrayList!string());
    }

    /// Creates a formatter with the default template and no excluded keys.
    static DefaultContentFormatter defaultConfig()
    {
        return builder().build();
    }

    /// Formats metadata in map traversal order, then inserts metadata and text.
    override string format(Document document, MetadataMode mode)
    {
        import flint.java.lang : NullPointerException;

        if (document is null)
            throw new NullPointerException();

        MetadataKeys excluded;
        if (mode == MetadataMode.EMBED)
            excluded = excludedEmbedMetadataKeys_;
        else if (mode == MetadataMode.INFERENCE)
            excluded = excludedInferenceMetadataKeys_;

        string metadata;
        bool hasEntry;
        if (mode != MetadataMode.NONE)
            document.getMetadata().forEach((string key, Any value) {
                if (excluded !is null && excluded.contains(key))
                    return;
                if (key is null)
                    throw new NullPointerException();
                if (hasEntry)
                    metadata ~= metadataSeparator_;
                hasEntry = true;
                const template_ = replacePlaceholder(metadataTemplate_, "{key}", key);
                const text = metadataValueText(value);
                metadata ~= replacePlaceholder(template_, "{value}", text);
            });

        const template_ = replacePlaceholder(textTemplate_, "{metadata_string}", metadata);
        const text = document.getText();
        const formatted = replacePlaceholder(template_, "{content}", text.isNull ? "" : text.get());
        return formatted.length == 0 ? "" : formatted;
    }

    /// Returns the metadata entry template.
    string getMetadataTemplate() const pure nothrow @nogc
    {
        return metadataTemplate_;
    }

    /// Returns the separator between metadata entries.
    string getMetadataSeparator() const pure nothrow @nogc
    {
        return metadataSeparator_;
    }

    /// Returns the formatted content template.
    string getTextTemplate() const pure nothrow @nogc
    {
        return textTemplate_;
    }

    /// Returns an unmodifiable view of the inference exclusions.
    MetadataKeys getExcludedInferenceMetadataKeys()
    {
        import flint.java.util : Collections;

        return Collections.unmodifiableList!string(excludedInferenceMetadataKeys_);
    }

    /// Returns an unmodifiable view of the embedding exclusions.
    MetadataKeys getExcludedEmbedMetadataKeys()
    {
        import flint.java.util : Collections;

        return Collections.unmodifiableList!string(excludedEmbedMetadataKeys_);
    }

    /// Configures a document formatter.
    static struct Builder
    {
        private string metadataTemplate = defaultMetadataTemplate;
        private string metadataSeparator = defaultMetadataSeparator;
        private string textTemplate = defaultTextTemplate;
        private MetadataKeys excludedInferenceMetadataKeys;
        private MetadataKeys excludedEmbedMetadataKeys;

        @disable this();

        private this(MetadataKeys inferenceKeys, MetadataKeys embedKeys)
        {
            excludedInferenceMetadataKeys = inferenceKeys;
            excludedEmbedMetadataKeys = embedKeys;
        }

        /// Uses the supplied formatter's settings.
        ref Builder from(DefaultContentFormatter formatter) return
        {
            import flint.java.lang : NullPointerException;

            if (formatter is null)
                throw new NullPointerException();
            return withExcludedEmbedMetadataKeys(formatter.getExcludedEmbedMetadataKeys())
                .withExcludedInferenceMetadataKeys(formatter.getExcludedInferenceMetadataKeys())
                .withMetadataSeparator(DocumentText(formatter.getMetadataSeparator()))
                .withMetadataTemplate(formatter.getMetadataTemplate()).withTextTemplate(formatter.getTextTemplate());
        }

        /// Sets a non-blank metadata entry template.
        ref Builder withMetadataTemplate(string template_) return
        {
            validateDocumentText(template_, "Metadata Template must not be empty");
            metadataTemplate = template_;
            return this;
        }

        /// Sets the entry separator. An empty separator is valid.
        ref Builder withMetadataSeparator(DocumentText separator) return
        {
            if (separator.isNull)
                throw new IllegalArgumentException("Metadata separator must not be empty");
            metadataSeparator = separator.get();
            return this;
        }

        /// Sets a non-blank content template.
        ref Builder withTextTemplate(string template_) return
        {
            validateDocumentText(template_, "Document's text template must not be empty");
            textTemplate = template_;
            return this;
        }

        /// Uses the supplied list of inference exclusions.
        ref Builder withExcludedInferenceMetadataKeys(MetadataKeys keys) return
        {
            if (keys is null)
                throw new IllegalArgumentException("Excluded inference metadata keys must not be null");
            excludedInferenceMetadataKeys = keys;
            return this;
        }

        /// Adds inference exclusions.
        ref Builder withExcludedInferenceMetadataKeys(string[] keys...) return
        {
            import flint.java.util : Arrays;

            if (keys is null)
                throw new IllegalArgumentException("Excluded inference metadata keys must not be null");
            excludedInferenceMetadataKeys.addAll(Arrays.asList(keys));
            return this;
        }

        /// Adds an empty batch of inference exclusions.
        ref Builder withExcludedInferenceMetadataKeys() return
        {
            import flint.java.util : Arrays;

            excludedInferenceMetadataKeys.addAll(Arrays.asList!string());
            return this;
        }

        /// Uses the supplied list of embedding exclusions.
        ref Builder withExcludedEmbedMetadataKeys(MetadataKeys keys) return
        {
            if (keys is null)
                throw new IllegalArgumentException("Excluded Embed metadata keys must not be null");
            excludedEmbedMetadataKeys = keys;
            return this;
        }

        /// Adds embedding exclusions.
        ref Builder withExcludedEmbedMetadataKeys(string[] keys...) return
        {
            import flint.java.util : Arrays;

            if (keys is null)
                throw new IllegalArgumentException("Excluded Embed metadata keys must not be null");
            excludedEmbedMetadataKeys.addAll(Arrays.asList(keys));
            return this;
        }

        /// Adds an empty batch of embedding exclusions.
        ref Builder withExcludedEmbedMetadataKeys() return
        {
            import flint.java.util : Arrays;

            excludedEmbedMetadataKeys.addAll(Arrays.asList!string());
            return this;
        }

        /// Builds a formatter using the current configuration.
        DefaultContentFormatter build()
        {
            return new DefaultContentFormatter(this);
        }
    }
}

// The placeholders are nonempty ASCII literals starting with a brace.
private string replacePlaceholder(string template_, string placeholder, string replacement) pure nothrow
{
    string result;
    size_t consumed;
    for (size_t offset; offset + placeholder.length <= template_.length;)
    {
        if (template_[offset] == '{' && template_[offset .. offset + placeholder.length] == placeholder)
        {
            result ~= template_[consumed .. offset];
            result ~= replacement;
            offset += placeholder.length;
            consumed = offset;
        }
        else
            ++offset;
    }
    return consumed == 0 ? template_ : result ~ template_[consumed .. $];
}

private string metadataValueText(Any value)
{
    import flint.engine.aot.objects : objectToString;
    import flint.java.lang : doubleToString, floatToString, NullPointerException;

    if (value.isNull)
        throw new NullPointerException();
    if (auto object = value.asObject())
    {
        const text = objectToString(object);
        if (text is null)
            throw new NullPointerException();
        return text;
    }
    switch (value.typeName)
    {
    case "double":
        return doubleToString(value.get!double);
    case "float":
        return floatToString(cast(float) value.get!double);
    default:
        return value.toString();
    }
}

/// A text document with an explicit identifier and metadata.
class Document
{
    private string id_;
    private DocumentText text_;
    private DocumentMetadataMap metadata_;
    /// Creates a text document with an explicit ID and a copy of its metadata.
    this(string id, DocumentText text, DocumentMetadataMap metadata)
    {
        validateDocumentText(id, "id cannot be null or empty");
        if (metadata is null)
            throw new IllegalArgumentException("metadata cannot be null");
        metadata.forEach((string key, Any) {
            if (key is null)
                throw new IllegalArgumentException("metadata cannot have null keys");
        });
        metadata.forEach((string, Any value) {
            if (value.isNull)
                throw new IllegalArgumentException("metadata cannot have null values");
        });
        if (text.isNull)
            throw new IllegalArgumentException("exactly one of text or media must be specified");

        id_ = id;
        text_ = text;
        metadata_ = copyContentMetadata(metadata);
    }

    /// Returns the unique document identifier.
    string getId() const pure nothrow @nogc
    {
        return id_;
    }

    /// Returns the text, preserving the distinction between empty and absent content.
    DocumentText getText() const pure nothrow @nogc
    {
        return text_;
    }

    /// Whether this document holds text content.
    bool isText() const pure nothrow @nogc
    {
        return !text_.isNull;
    }

    /// Returns the document's own metadata map.
    DocumentMetadataMap getMetadata()
    {
        return metadata_;
    }

    /// Formats the document using the supplied formatter and mode.
    string getFormattedContent(ContentFormatter formatter, MetadataMode mode)
    {
        return getFormattedContent(formatter, Nullable!MetadataMode(mode));
    }

    /// Preserves Java's null-mode validation (R5).
    string getFormattedContent(ContentFormatter formatter, Nullable!MetadataMode mode)
    {
        if (formatter is null)
            throw new IllegalArgumentException("formatter must not be null");
        if (mode.isNull)
            throw new IllegalArgumentException("Metadata mode must not be null");
        return formatter.format(this, mode.get());
    }

    /// Compares document data with another instance of the same runtime class.
    bool equals(Object other)
    {
        if (other is this)
            return true;
        auto that = cast(Document) other;
        return that !is null && typeid(this) is typeid(that) && id_ == that.id_
            && text_.isNull == that.text_.isNull && (text_.isNull
                    || text_.get() == that.text_.get()) && metadata_.equals(cast(Object) that.metadata_);
    }

    /// Hashes the document fields in Java's order, including absent media and score.
    int hashCode()
    {
        import flint.java.lang : stringHashCode;

        int hash = 31 + stringHashCode(id_);
        hash = 31 * hash + (text_.isNull ? 0 : stringHashCode(text_.get()));
        hash *= 31; // No media on this construction path.
        hash = 31 * hash + metadata_.hashCode();
        return 31 * hash; // No score on this construction path.
    }

    /// Renders the document data, including absent media and score.
    override string toString()
    {
        const text = text_.isNull ? "null" : text_.get();
        return "Document{id='" ~ id_ ~ "', text='" ~ text ~ "', media='null', metadata=" ~ metadata_.toString()
            ~ ", score=null}";
    }

    mixin JavaObject;
}

private void validateDocumentText(string text, string message)
{
    if (!hasDocumentText(text))
        throw new IllegalArgumentException(message);
}

package(flint.ai) bool hasDocumentText(string text) pure nothrow @nogc
{
    import flint.engine.aot.text : decodeUtf8;

    // Match Java Character.isWhitespace without loading the wider flint.util module.
    size_t offset;
    while (offset < text.length)
    {
        const point = decodeUtf8(text, offset);
        switch (point)
        {
        case '\t', '\n', '\v', '\f', '\r', 0x1c, 0x1d, 0x1e, 0x1f, ' ', 0x1680, 0x2028, 0x2029, 0x205f, 0x3000:
            break;
        default:
            if (point < 0x2000 || point > 0x200a || point == 0x2007)
                return true;
            break;
        }
    }
    return false;
}

private alias DocumentList = List!Document;

/// Supplies documents from a source.
interface DocumentReader : Supplier!DocumentList
{
    /// Reads the documents.
    DocumentList read();

    /// Supplies the reader's default implementation (R3).
    mixin template Defaults()
    {
        import flint.ai.document : Document, DocumentReader;
        import flint.java.util : List;

        override List!Document read()
        {
            DocumentReader reader = this;
            return reader.get();
        }
    }
}

/// Accepts documents for writing.
interface DocumentWriter : Consumer!DocumentList
{
    /// Writes the documents.
    void write(DocumentList documents);

    /// Supplies the writer's default implementation (R3).
    mixin template Defaults()
    {
        import flint.ai.document : Document, DocumentWriter;
        import flint.java.util : List;

        override void write(List!Document documents)
        {
            DocumentWriter writer = this;
            writer.accept(documents);
        }
    }
}

/// Transforms a list of documents.
interface DocumentTransformer : Function!(DocumentList, DocumentList)
{
    /// Returns the transformed documents.
    DocumentList transform(DocumentList documents);

    /// Supplies the transformer's default implementation (R3).
    mixin template Defaults()
    {
        import flint.ai.document : Document, DocumentTransformer;
        import flint.java.util : List;

        override List!Document transform(List!Document documents)
        {
            DocumentTransformer transformer = this;
            return transformer.apply(documents);
        }
    }
}
