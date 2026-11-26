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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/document/{DocumentMetadata,MetadataMode}.java
// Modified by the Flint authors.
module flint.ai.document;

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
