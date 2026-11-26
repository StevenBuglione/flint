/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/http/converter/ResourceRegionHttpMessageConverterTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors.
+/
module flint.http.converter.resource_region_http_message_converter_tests;

import flint.core.convert : TypeDescriptor;
import flint.core.io : ByteArrayResource, InputStreamResource, Resource;
import flint.core.io.support : ResourceRegion;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.http : HttpHeaders, HttpRange, MediaType, StreamingHttpOutputMessage;
import flint.http.converter : GenericHttpMessageConverter, ResourceRegionHttpMessageConverter;
import flint.http.testfixture.mock_http_messages : MockHttpOutputMessage;
import flint.java.io : ByteArrayInputStream, ByteArrayOutputStream;
import flint.java.util : List;
import std.algorithm.searching : startsWith;
import std.ascii : isAlphaNum;

@safe:

private enum fixture = "Spring Framework test resource content.";

private Resource resource()
{
    return new ByteArrayResource(cast(immutable(ubyte)[]) fixture);
}

@("ResourceRegionHttpMessageConverterTests.canReadResource")
unittest
{
    auto converter = new ResourceRegionHttpMessageConverter();
    assert(!converter.canRead(typeNameOf!Resource, &MediaType.APPLICATION_OCTET_STREAM));
    assert(!converter.canRead(typeNameOf!Resource, &MediaType.ALL));
    assert(!converter.canRead(typeNameOf!(List!Object), &MediaType.APPLICATION_OCTET_STREAM));
    assert(!converter.canRead(TypeDescriptor.valueOf!Resource(), null, &MediaType.ALL));
}

@("ResourceRegionHttpMessageConverterTests.canWriteResource")
unittest
{
    auto converter = new ResourceRegionHttpMessageConverter();
    auto region = TypeDescriptor.valueOf!ResourceRegion();
    assert(converter.canWrite(region, null, &MediaType.APPLICATION_OCTET_STREAM));
    assert(converter.canWrite(typeNameOf!ResourceRegion, &MediaType.ALL));
    assert(!converter.canWrite(TypeDescriptor.valueOf!Object(), null, &MediaType.ALL));
}

@("ResourceRegionHttpMessageConverterTests.canWriteResourceCollection")
unittest
{
    GenericHttpMessageConverter converter = new ResourceRegionHttpMessageConverter();
    auto regions = TypeDescriptor.valueOf!(List!ResourceRegion)();
    assert(converter.canWrite(regions, null, &MediaType.APPLICATION_OCTET_STREAM));
    assert(converter.canWrite(regions, null, &MediaType.ALL));
    assert(!converter.canWrite("flint.java.util.List", &MediaType.APPLICATION_OCTET_STREAM));
    assert(!converter.canWrite("flint.java.util.List", &MediaType.ALL));
    assert(!converter.canWrite(TypeDescriptor.valueOf!(List!Object)(), null, &MediaType.ALL));
}

@("ResourceRegionHttpMessageConverterTests.shouldWritePartialContentByteRange")
unittest
{
    auto converter = new ResourceRegionHttpMessageConverter();
    auto message = new MockHttpOutputMessage();
    converter.write(Any.of(HttpRange.createByteRange(0, 5).toResourceRegion(resource())),
            &MediaType.TEXT_PLAIN, message);
    auto headers = message.getHeaders();
    assert(*headers.getContentType() == MediaType.TEXT_PLAIN);
    assert(headers.getContentLength() == 6);
    assert(headers.get(HttpHeaders.CONTENT_RANGE) == ["bytes 0-5/39"]);
    assert(message.getBodyAsString() == "Spring");
}

@("ResourceRegionHttpMessageConverterTests.shouldWritePartialContentByteRangeNoEnd")
unittest
{
    auto converter = new ResourceRegionHttpMessageConverter();
    auto message = new MockHttpOutputMessage();
    converter.write(Any.of(HttpRange.createByteRange(7).toResourceRegion(resource())), &MediaType.TEXT_PLAIN, message);
    auto headers = message.getHeaders();
    assert(*headers.getContentType() == MediaType.TEXT_PLAIN);
    assert(headers.getContentLength() == 32);
    assert(headers.get(HttpHeaders.CONTENT_RANGE) == ["bytes 7-38/39"]);
    assert(message.getBodyAsString() == "Framework test resource content.");
}

private void checkMultipart(string ranges, scope const(string[2])[] expected)
{
    auto converter = new ResourceRegionHttpMessageConverter();
    auto message = new MockHttpOutputMessage();
    auto regions = HttpRange.toResourceRegions(HttpRange.parseRanges(ranges), resource());
    converter.write(Any.of(regions), TypeDescriptor.valueOf!(List!ResourceRegion)(),
            &MediaType.TEXT_PLAIN, message);
    enum prefix = "multipart/byteranges;boundary=";
    auto contentType = message.getHeaders().getContentType().toString();
    assert(contentType.startsWith(prefix));
    const token = contentType[prefix.length .. $];
    assert(token.length >= 30 && token.length <= 40);
    foreach (c; token)
        assert(isAlphaNum(c) || c == '-' || c == '_');
    string boundary = "--" ~ token;
    string wire;
    foreach (ref part; expected)
        wire ~= "\r\n" ~ boundary ~ "\r\nContent-Type: text/plain\r\nContent-Range: bytes "
            ~ part[0] ~ "\r\n\r\n" ~ part[1];
    assert(message.getBodyAsString() == wire ~ "\r\n" ~ boundary ~ "--");
}

@("ResourceRegionHttpMessageConverterTests.partialContentMultipleByteRanges")
unittest
{
    checkMultipart("bytes=0-5,7-15,17-20,22-38", [
        ["0-5/39", "Spring"], ["7-15/39", "Framework"], ["17-20/39", "test"],
        ["22-38/39", "resource content."]
    ]);
}

@("ResourceRegionHttpMessageConverterTests.partialContentMultipleByteRangesInRandomOrderAndOverlapping")
unittest
{
    checkMultipart("bytes=7-15,0-5,17-20,20-29", [
        ["7-15/39", "Framework"], ["0-5/39", "Spring"], ["17-20/39", "test"],
        ["20-29/39", "t resource"]
    ]);
}

@("ResourceRegionHttpMessageConverterTests.applicationOctetStreamDefaultContentType")
unittest
{
    auto body = new class ByteArrayResource
    {
        this()
        {
            super(cast(immutable(ubyte)[]) "Spring Framework");
        }

        override string getFilename()
        {
            return "spring.dat";
        }

        override long contentLength()
        {
            return 12;
        }
    };
    auto converter = new ResourceRegionHttpMessageConverter();
    auto message = new MockHttpOutputMessage();
    auto regions = List!ResourceRegion.of(HttpRange.createByteRange(0, 5).toResourceRegion(body));
    converter.write(Any.of(regions), null, message);
    assert(*message.getHeaders().getContentType() == MediaType.APPLICATION_OCTET_STREAM);
    assert(message.getHeaders().getFirst(HttpHeaders.CONTENT_RANGE) == "bytes 0-5/12");
    assert(message.getBodyAsString() == "Spring");
}

private final class DeferredMessage : MockHttpOutputMessage, StreamingHttpOutputMessage
{
    mixin StreamingHttpOutputMessage.Defaults;
    StreamingHttpOutputMessage.Body body;

    override void setBody(StreamingHttpOutputMessage.Body value)
    {
        body = value;
    }
}

@("Flint.ResourceRegionHttpMessageConverter.deferredStreaming")
unittest
{
    auto converter = new ResourceRegionHttpMessageConverter();
    auto message = new DeferredMessage();
    auto region = HttpRange.createByteRange(0, 5).toResourceRegion(resource());
    converter.write(Any.of(region), TypeDescriptor.valueOf!ResourceRegion(), &MediaType.TEXT_PLAIN, message);
    assert(message.getBodyAsBytes().length == 0 && message.body.repeatable());

    auto output = new ByteArrayOutputStream();
    message.body.writeTo(output);
    assert(output.toByteArray() == cast(const(ubyte)[]) "Spring");
    assert(message.getHeaders().getFirst(HttpHeaders.CONTENT_RANGE) == "bytes 0-5/39");

    auto stream = new InputStreamResource(new ByteArrayInputStream(cast(const(ubyte)[]) fixture));
    assert(!converter.canWriteRepeatedly(Any.of(new ResourceRegion(stream, 0, 6)), null));

    ubyte[1] buffer = [42];
    StreamingHttpOutputMessage sink = message;
    sink.setBody(buffer[]);
    buffer[0] = 0;
    auto deferred = new ByteArrayOutputStream();
    assert(message.body.repeatable());
    message.body.writeTo(deferred);
    assert(deferred.toByteArray() == [42]);
}
