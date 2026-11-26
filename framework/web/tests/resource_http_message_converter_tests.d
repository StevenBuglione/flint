/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/http/converter/ResourceHttpMessageConverterTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors.
+/
module flint.http.converter.resource_http_message_converter_tests;

import flint.core.io : ByteArrayResource, InputStreamResource, Resource;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.http : HttpHeaders, MediaType, StreamingHttpOutputMessage;
import flint.http.converter : HttpMessageNotReadableException, ResourceHttpMessageConverter;
import flint.http.testfixture.mock_http_messages : MockHttpInputMessage, MockHttpOutputMessage;
import flint.java.io : ByteArrayInputStream, ByteArrayOutputStream, FileNotFoundException, InputStream;
import flint.java.lang : IllegalStateException, NullPointerException;

@safe:

// The converter transports opaque image bytes and determines the media type from the filename.
private immutable ubyte[] image = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0xff, 0xd9];

private MockHttpInputMessage imageMessage(string disposition = null)
{
    auto input = new MockHttpInputMessage(image);
    input.getHeaders().setContentType(MediaType.IMAGE_JPEG);
    if (disposition !is null)
        input.getHeaders().set(HttpHeaders.CONTENT_DISPOSITION, disposition);
    return input;
}

private void assertUnreadable(scope void delegate() @safe read)
{
    try
        read();
    catch (HttpMessageNotReadableException)
        return;
    assert(false, "expected HttpMessageNotReadableException");
}

private class CustomResource : ByteArrayResource
{
    this(immutable(ubyte)[] bytes)
    {
        super(bytes);
    }
}

private class CustomStreamResource : InputStreamResource
{
    this(InputStream stream)
    {
        super(stream);
    }
}

@("ResourceHttpMessageConverterTests.canReadResource")
unittest
{
    auto converter = new ResourceHttpMessageConverter();
    assert(converter.canRead(typeNameOf!Resource, &MediaType.APPLICATION_OCTET_STREAM));
    assert(converter.canRead(typeNameOf!ByteArrayResource, &MediaType.APPLICATION_OCTET_STREAM));
}

@("ResourceHttpMessageConverterTests.canWriteResource")
unittest
{
    auto converter = new ResourceHttpMessageConverter();
    assert(converter.canWrite(typeNameOf!Resource, &MediaType.APPLICATION_OCTET_STREAM));
    assert(converter.canWrite(typeNameOf!Resource, &MediaType.ALL));
    assert(converter.canWrite(typeNameOf!ByteArrayResource, &MediaType.ALL));
}

@("ResourceHttpMessageConverterTests.shouldReadImageResource")
unittest
{
    auto input = imageMessage("attachment; filename=\"yourlogo.jpg\"");
    auto resource = new ResourceHttpMessageConverter().read(typeNameOf!Resource, input).get!Resource;
    assert(resource.getInputStream().readAllBytes() == image);
    assert(resource.getFilename() == "yourlogo.jpg");
}

@("ResourceHttpMessageConverterTests.shouldNotReadAsUnknownType")
unittest
{
    auto input = imageMessage("attachment; filename=\"yourlogo.jpg\"");
    auto converter = new ResourceHttpMessageConverter();
    assertUnreadable(() { converter.read(typeNameOf!CustomResource, input); });
}

@("ResourceHttpMessageConverterTests.shouldReadInputStreamResource")
unittest
{
    auto input = imageMessage("attachment; filename=\"yourlogo.jpg\"");
    input.getHeaders().setContentLength(123);
    auto resource = new ResourceHttpMessageConverter().read(typeNameOf!InputStreamResource, input).get!Resource;
    assert(cast(InputStreamResource) resource !is null);
    assert(resource.getFilename() == "yourlogo.jpg");
    assert(resource.contentLength() == 123);
    assert(resource.getInputStream().readAllBytes() == image);
    try
        resource.getInputStream();
    catch (IllegalStateException)
        return;
    assert(false, "input stream resource accepted a second read");
}

@("ResourceHttpMessageConverterTests.shouldNotReadInputStreamResource")
unittest
{
    auto converter = new ResourceHttpMessageConverter(false);
    assertUnreadable(() { converter.read(typeNameOf!InputStreamResource, imageMessage()); });
}

@("ResourceHttpMessageConverterTests.shouldNotReadStreamResourceAsUnknownType")
unittest
{
    auto converter = new ResourceHttpMessageConverter();
    assertUnreadable(() { converter.read(typeNameOf!CustomStreamResource, imageMessage()); });
}

@("ResourceHttpMessageConverterTests.shouldWriteImageResource")
unittest
{
    auto output = new MockHttpOutputMessage();
    auto resource = new class ByteArrayResource
    {
        this()
        {
            super(image);
        }

        override string getFilename()
        {
            return "logo.jpg";
        }
    };
    auto converter = new ResourceHttpMessageConverter();
    converter.write(Any.of(resource), null, output);
    assert(*output.getHeaders().getContentType() == MediaType.IMAGE_JPEG);
    assert(output.getHeaders().getContentLength() == image.length);
    assert(output.getBodyAsBytes() == image);
}

@("ResourceHttpMessageConverterTests.writeByteArrayNullMediaType")
unittest
{
    auto output = new MockHttpOutputMessage();
    auto resource = new ByteArrayResource([1, 2, 3]);
    new ResourceHttpMessageConverter().write(Any.of(resource), null, output);
    assert(output.getBodyAsBytes() == [1, 2, 3]);
}

private final class TestStream : InputStream
{
    private bool errorsOnRead;
    bool closed;

    this(bool errorsOnRead)
    {
        this.errorsOnRead = errorsOnRead;
    }

    override int read()
    {
        if (errorsOnRead)
            throw new NullPointerException("read");
        return -1;
    }

    override void close()
    {
        closed = true;
        if (!errorsOnRead)
            throw new NullPointerException("close");
    }
}

private final class TestResource : ByteArrayResource
{
    private InputStream stream;

    this(InputStream stream)
    {
        super(cast(immutable(ubyte)[]) "");
        this.stream = stream;
    }

    override InputStream getInputStream()
    {
        if (stream is null)
            throw new FileNotFoundException("missing");
        return stream;
    }
}

private void writeEmpty(TestResource resource)
{
    auto output = new MockHttpOutputMessage();
    new ResourceHttpMessageConverter().write(Any.of(resource), &MediaType.APPLICATION_OCTET_STREAM, output);
    assert(output.getHeaders().getContentLength() == 0);
    assert(output.getBodyAsBytes().length == 0);
}

@("ResourceHttpMessageConverterTests.writeContentNotGettingInputStream")
unittest
{
    writeEmpty(new TestResource(null));
}

@("ResourceHttpMessageConverterTests.writeContentNotClosingInputStream")
unittest
{
    auto stream = new TestStream(false);
    writeEmpty(new TestResource(stream));
    assert(stream.closed);
}

@("ResourceHttpMessageConverterTests.writeContentInputStreamThrowingNullPointerException")
unittest
{
    auto stream = new TestStream(true);
    writeEmpty(new TestResource(stream));
    assert(stream.closed);
}

private final class DeferredResourceMessage : MockHttpOutputMessage, StreamingHttpOutputMessage
{
    mixin StreamingHttpOutputMessage.Defaults;
    StreamingHttpOutputMessage.Body body;

    override void setBody(StreamingHttpOutputMessage.Body value)
    {
        body = value;
    }
}

@("Flint.ResourceHttpMessageConverter.streamingWrite")
unittest
{
    auto converter = new ResourceHttpMessageConverter();
    Resource resource = new InputStreamResource(new ByteArrayInputStream(image));
    auto output = new DeferredResourceMessage();
    converter.write(Any.of(resource), null, output);
    assert(output.getHeaders().getContentLength() == -1);
    assert(output.getBodyAsBytes().length == 0 && !output.body.repeatable());
    auto bytes = new ByteArrayOutputStream();
    output.body.writeTo(bytes);
    assert(bytes.toByteArray() == image);
}

@("Flint.ResourceHttpMessageConverter.extendedFilename")
unittest
{
    auto input = imageMessage("attachment; filename=\"a;b.png\"; filename*=UTF-8''caf%C3%A9.png");
    auto resource = new ResourceHttpMessageConverter().read(typeNameOf!Resource, input).get!Resource;
    assert(resource.getFilename() == "café.png");
}

@("Flint.ResourceHttpMessageConverter.ownsBufferedInput")
unittest
{
    auto bytes = image.dup;
    auto input = new MockHttpInputMessage(bytes);
    auto resource = new ResourceHttpMessageConverter().read(typeNameOf!InputStreamResource, input).get!Resource;
    bytes[] = 0;
    assert(resource.contentLength() == image.length);
    assert(resource.getInputStream().readAllBytes() == image);
}
