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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/document/{ContentFormatter,Document,DocumentMetadata,MetadataMode}.java
// Modified by the Flint authors.
module flint.ai.document;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : HashMap, Map;
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

/// A text document with an explicit identifier and metadata.
class Document
{
    private string id_;
    private DocumentText text_;
    private DocumentMetadataMap metadata_;
    /// Creates a text document with an explicit ID and a copy of its metadata.
    this(string id, DocumentText text, DocumentMetadataMap metadata)
    {
        validateId(id);
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
        metadata_ = new HashMap!(string, Any)(metadata);
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

    private static void validateId(string id)
    {
        import flint.engine.aot.text : decodeUtf8;

        // Match Java Character.isWhitespace without retaining flint.util's archive.
        size_t offset;
        while (offset < id.length)
        {
            const point = decodeUtf8(id, offset);
            switch (point)
            {
            case '\t', '\n', '\v', '\f', '\r', 0x1c, 0x1d, 0x1e, 0x1f, ' ', 0x1680, 0x2028, 0x2029,
                    0x205f, 0x3000:
                    break;
            default:
                if (point < 0x2000 || point > 0x200a || point == 0x2007)
                    return;
                break;
            }
        }
        throw new IllegalArgumentException("id cannot be null or empty");
    }
}
