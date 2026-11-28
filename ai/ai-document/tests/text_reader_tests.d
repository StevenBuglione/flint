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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/test/java/org/springframework/ai/reader/TextReaderTests.java
// Modified by the Flint authors.
module text_reader_tests;

import flint.ai.document : Document;
import flint.ai.reader : TextReader;
import flint.core.io : AbstractResource, ByteArrayResource, FileSystemResource, Resource;
import flint.engine.aot.any : Any;
import flint.java.io : ByteArrayInputStream, InputStream;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : List;
import std.exception : assertThrown;
import std.string : representation;

@safe:

private immutable(ubyte)[] bytes(string text)
{
    return text.representation;
}

private string sourceOf(Document document)
{
    return document.getMetadata().get(TextReader.SOURCE_METADATA).get!string();
}

private string metadataText(Document document, string key)
{
    return document.getMetadata().get(key).get!string();
}

@("loadText")
unittest
{
    // Requires TokenTextSplitter from the deferred org.springframework.ai.transformer.splitter package.
}

@("loadTextFromByteArrayResource")
unittest
{
    // The default ByteArrayResource description is the core port's empty string, not Java's
    // "resource loaded from byte array" (docs/spring/java-differences.md); the reader must still
    // report the resource's own description as the source.
    Resource defaultByteArrayResource = new ByteArrayResource(bytes("Test content"));
    TextReader defaultTextReader = new TextReader(defaultByteArrayResource);
    defaultTextReader.getCustomMetadata().put("customKey", Any.of("DefaultValue"));

    List!Document defaultDocuments = defaultTextReader.read();

    assert(defaultDocuments.size() == 1);
    Document defaultDocument = defaultDocuments.get(0);
    assert(metadataText(defaultDocument, "customKey") == "DefaultValue");
    assert(metadataText(defaultDocument, TextReader.CHARSET_METADATA) == "UTF-8");
    assert(sourceOf(defaultDocument) == defaultByteArrayResource.getDescription());
    assert(defaultDocument.getText().get() == "Test content");

    Resource customByteArrayResource = new ByteArrayResource(bytes("Another test content"),
            "Custom byte array resource");
    TextReader customTextReader = new TextReader(customByteArrayResource);
    customTextReader.getCustomMetadata().put("customKey", Any.of("CustomValue"));

    List!Document customDocuments = customTextReader.read();

    assert(customDocuments.size() == 1);
    Document customDocument = customDocuments.get(0);
    assert(metadataText(customDocument, "customKey") == "CustomValue");
    assert(metadataText(customDocument, TextReader.CHARSET_METADATA) == "UTF-8");
    assert(sourceOf(customDocument) == "Byte array resource [Custom byte array resource]");
    assert(customDocument.getText().get() == "Another test content");
}

@("loadEmptyText")
unittest
{
    Resource emptyResource = new ByteArrayResource(bytes(""));
    TextReader textReader = new TextReader(emptyResource);

    List!Document documents = textReader.read();

    assert(documents.size() == 1);
    assert(documents.get(0).getText().get() == "");
    assert(metadataText(documents.get(0), TextReader.CHARSET_METADATA) == "UTF-8");
}

@("loadTextWithOnlyWhitespace")
unittest
{
    Resource whitespaceResource = new ByteArrayResource(bytes("   \n\t\r\n   "));
    TextReader textReader = new TextReader(whitespaceResource);

    List!Document documents = textReader.read();

    assert(documents.size() == 1);
    assert(documents.get(0).getText().get() == "   \n\t\r\n   ");
}

@("loadTextWithMultipleNewlines")
unittest
{
    const content = "Line 1\n\n\nLine 4\r\nLine 5\r\n\r\nLine 7";
    Resource resource = new ByteArrayResource(bytes(content));
    TextReader textReader = new TextReader(resource);

    List!Document documents = textReader.read();

    assert(documents.size() == 1);
    assert(documents.get(0).getText().get() == content);
}

@("customMetadataIsPreserved")
unittest
{
    Resource resource = new ByteArrayResource(bytes("Test"));
    TextReader textReader = new TextReader(resource);

    textReader.getCustomMetadata().put("author", Any.of("Author"));
    textReader.getCustomMetadata().put("version", Any.of("1.0"));
    textReader.getCustomMetadata().put("category", Any.of("test"));

    List!Document documents = textReader.read();

    assert(documents.size() == 1);
    Document document = documents.get(0);
    assert(metadataText(document, "author") == "Author");
    assert(metadataText(document, "version") == "1.0");
    assert(metadataText(document, "category") == "test");
}

@("resourceDescriptionHandling")
unittest
{
    import std.file : exists, mkdirRecurse, tempDir, write;
    import std.path : buildPath;

    const dir = buildPath(tempDir(), "flint-text-reader-tests");
    if (!exists(dir))
        mkdirRecurse(dir);
    const path = buildPath(dir, "test-file.txt");
    write(path, "File content");

    TextReader fileReader = new TextReader(new FileSystemResource(path));
    List!Document documents = fileReader.read();

    assert(documents.size() == 1);
    assert(sourceOf(documents.get(0)) == "test-file.txt");
}

@("multipleCallsToGetReturnSameResult")
unittest
{
    Resource resource = new ByteArrayResource(bytes("Consistent content"));
    TextReader textReader = new TextReader(resource);
    textReader.getCustomMetadata().put("test", Any.of("value"));

    List!Document firstCall = textReader.read();
    List!Document secondCall = textReader.read();

    assert(firstCall.size() == 1);
    assert(secondCall.size() == 1);
    assert(firstCall.get(0).getText().get() == secondCall.get(0).getText().get());
    assert(sourceOf(firstCall.get(0)) == sourceOf(secondCall.get(0)));
    assert(metadataText(firstCall.get(0), "test") == metadataText(secondCall.get(0), "test"));
}

@("resourceWithoutExtension")
unittest
{
    import std.file : exists, mkdirRecurse, tempDir, write;
    import std.path : buildPath;

    const dir = buildPath(tempDir(), "flint-text-reader-tests");
    if (!exists(dir))
        mkdirRecurse(dir);
    const path = buildPath(dir, "no-extension-file");
    write(path, "Content without extension");

    TextReader textReader = new TextReader(new FileSystemResource(path));
    List!Document documents = textReader.read();

    assert(documents.size() == 1);
    assert(documents.get(0).getText().get() == "Content without extension");
    assert(sourceOf(documents.get(0)) == "no-extension-file");
}

@("closesTheResourceInputStream")
unittest
{
    auto resource = new TrackingResource(bytes("Test content"));

    new TextReader(resource).read();

    assert(resource.closed);
}

private final class TrackingStream : InputStream
{
    private InputStream inner_;
    private TrackingResource owner_;

    this(InputStream inner, TrackingResource owner)
    {
        inner_ = inner;
        owner_ = owner;
    }

    override int read()
    {
        return inner_.read();
    }

    override void close()
    {
        owner_.markClosed();
        inner_.close();
    }
}

private final class TrackingResource : AbstractResource
{
    private immutable(ubyte)[] data_;
    private bool closed_;

    this(immutable(ubyte)[] content)
    {
        data_ = content;
    }

    bool closed() const pure nothrow @nogc
    {
        return closed_;
    }

    package void markClosed() pure nothrow @nogc
    {
        closed_ = true;
    }

    override InputStream getInputStream()
    {
        closed_ = false;
        return new TrackingStream(new ByteArrayInputStream(data_), this);
    }

    override string getDescription()
    {
        return "tracking resource";
    }
}

@("a null resource is rejected")
unittest
{
    assertThrown!IllegalArgumentException(new TextReader(cast(Resource) null));
}

@("a null charset name is rejected")
unittest
{
    auto reader = new TextReader(new ByteArrayResource(bytes("x")));
    assertThrown!IllegalArgumentException(reader.setCharset(null));
}
