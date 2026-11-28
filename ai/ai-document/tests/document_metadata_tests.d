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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/test/java/org/springframework/ai/document/DocumentMetadataTests.java
// Modified by the Flint authors.
module document_metadata_tests;

import flint.ai.document : DocumentMetadata, MetadataMode;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import std.exception : assertThrown;

@safe:

@("distanceKey")
unittest
{
    assert(DocumentMetadata.DISTANCE.value() == "distance");
    assert(DocumentMetadata.DISTANCE.toString() == "distance");
}

@("contentRefKey")
unittest
{
    assert(DocumentMetadata.CONTENT_REF.value() == "content_ref");
    assert(DocumentMetadata.CONTENT_REF.toString() == "content_ref");
}

@("document metadata keeps the Java names, ordinals and independent values arrays")
unittest
{
    auto keys = DocumentMetadata.values();
    assert(keys == [DocumentMetadata.DISTANCE, DocumentMetadata.CONTENT_REF]);
    assert(keys[0].name() == "DISTANCE" && keys[0].ordinal() == 0);
    assert(keys[1].name() == "CONTENT_REF" && keys[1].ordinal() == 1);
    assert(DocumentMetadata.valueOf("DISTANCE") == keys[0]);
    assert(DocumentMetadata.valueOf("CONTENT_REF") == keys[1]);
    assertThrown!NullPointerException(DocumentMetadata.valueOf(null));
    assertThrown!IllegalArgumentException(DocumentMetadata.valueOf("content_ref"));
    keys[0] = keys[1];
    assert(DocumentMetadata.values()[0] == DocumentMetadata.DISTANCE);
}

@("metadata mode keeps Java declaration order")
unittest
{
    import std.traits : EnumMembers;

    assert([EnumMembers!MetadataMode] == [
        MetadataMode.ALL, MetadataMode.EMBED, MetadataMode.INFERENCE, MetadataMode.NONE
    ]);
}
