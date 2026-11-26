/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/http/HttpRangeTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors.
+/
module flint.http.http_range_tests;

import flint.core.io : ByteArrayResource, InputStreamResource;
import flint.http : HttpHeaders, HttpRange;
import flint.java.io : ByteArrayInputStream, IOException, InputStream;
import flint.java.lang : IllegalArgumentException, Long;
import flint.java.util : List;

@safe:

private enum long lastModified = 1_660_000_000_000L;

private void rejectsRange(scope void delegate() @safe action)
{
    try
        action();
    catch (IllegalArgumentException)
        return;
    assert(false, "expected IllegalArgumentException");
}

private HttpHeaders rangeRequestHeaders()
{
    HttpHeaders headers;
    headers.setRange(List!HttpRange.of(HttpRange.createByteRange(0, 1)));
    return headers;
}

private List!HttpRange resolveWithIfRange(string ifRange, string tag)
{
    auto request = rangeRequestHeaders();
    request.set(HttpHeaders.IF_RANGE, ifRange);
    HttpHeaders response;
    response.setETag(tag);
    return HttpRange.resolveRanges(request, response);
}

@("HttpRangeTests.invalidFirstPosition")
unittest
{
    rejectsRange(() { HttpRange.createByteRange(-1); });
}

@("HttpRangeTests.invalidLastLessThanFirst")
unittest
{
    rejectsRange(() { HttpRange.createByteRange(10, 9); });
}

@("HttpRangeTests.invalidSuffixLength")
unittest
{
    rejectsRange(() { HttpRange.createSuffixRange(-1); });
}

@("HttpRangeTests.byteRange")
unittest
{
    auto range = HttpRange.createByteRange(0, 499);
    assert(range.getRangeStart(1_000) == 0);
    assert(range.getRangeEnd(1_000) == 499);
}

@("HttpRangeTests.byteRangeWithoutLastPosition")
unittest
{
    auto range = HttpRange.createByteRange(9_500);
    assert(range.getRangeStart(10_000) == 9_500);
    assert(range.getRangeEnd(10_000) == 9_999);
}

@("HttpRangeTests.byteRangeOfZeroLength")
unittest
{
    auto range = HttpRange.createByteRange(9_500, 9_500);
    assert(range.getRangeStart(10_000) == 9_500);
    assert(range.getRangeEnd(10_000) == 9_500);
}

@("HttpRangeTests.suffixRange")
unittest
{
    auto range = HttpRange.createSuffixRange(500);
    assert(range.getRangeStart(1_000) == 500);
    assert(range.getRangeEnd(1_000) == 999);
}

@("HttpRangeTests.suffixRangeShorterThanRepresentation")
unittest
{
    auto range = HttpRange.createSuffixRange(500);
    assert(range.getRangeStart(350) == 0);
    assert(range.getRangeEnd(350) == 349);
}

@("HttpRangeTests.parseRanges")
unittest
{
    auto ranges = HttpRange.parseRanges("bytes=0-0,500-,-1");
    assert(ranges.size() == 3);
    assert(ranges.get(0).getRangeStart(1_000) == 0);
    assert(ranges.get(0).getRangeEnd(1_000) == 0);
    assert(ranges.get(1).getRangeStart(1_000) == 500);
    assert(ranges.get(1).getRangeEnd(1_000) == 999);
    assert(ranges.get(2).getRangeStart(1_000) == 999);
    assert(ranges.get(2).getRangeEnd(1_000) == 999);
}

@("HttpRangeTests.resolveRangesWithoutIfRange")
unittest
{
    assert(HttpRange.resolveRanges(rangeRequestHeaders(), HttpHeaders.init).size() == 1);
}

@("HttpRangeTests.resolveRangesWithMatchingIfRangeETag")
unittest
{
    assert(resolveWithIfRange("\"current\"", "\"current\"").size() == 1);
}

@("HttpRangeTests.resolveRangesWithNonMatchingIfRangeETag")
unittest
{
    assert(resolveWithIfRange("\"stale\"", "\"current\"").isEmpty());
    assert(resolveWithIfRange("W/\"current\"", "W/\"current\"").isEmpty());
    assert(resolveWithIfRange("\"current\"", "W/\"current\"").isEmpty());
}

@("HttpRangeTests.resolveRangesWithMatchingIfRangeDate")
unittest
{
    auto request = rangeRequestHeaders();
    request.setDate(HttpHeaders.IF_RANGE, lastModified);
    HttpHeaders response;
    response.setLastModified(lastModified);
    assert(HttpRange.resolveRanges(request, response).size() == 1);
}

@("HttpRangeTests.resolveRangesWithNonMatchingIfRangeDate")
unittest
{
    auto request = rangeRequestHeaders();
    request.setDate(HttpHeaders.IF_RANGE, lastModified - 1_000);
    HttpHeaders response;
    response.setLastModified(lastModified);
    assert(HttpRange.resolveRanges(request, response).isEmpty());
}

@("HttpRangeTests.resolveRangesIgnoresInvalidRangeWhenIfRangeDoesNotMatch")
unittest
{
    HttpHeaders request, response;
    request.set(HttpHeaders.RANGE, "invalid");
    request.set(HttpHeaders.IF_RANGE, "\"stale\"");
    response.setETag("\"current\"");
    assert(HttpRange.resolveRanges(request, response).isEmpty());
}

@("HttpRangeTests.parseRangesValidations")
unittest
{
    string ranges = "bytes=0-0";
    foreach (i; 0 .. 99)
        ranges ~= "," ~ Long.toString(i) ~ "-" ~ Long.toString(i + 1);
    assert(HttpRange.parseRanges(ranges).size() == 100);
    ranges ~= ",99-100";
    rejectsRange(() { HttpRange.parseRanges(ranges); });
}

@("HttpRangeTests.rangeToString")
unittest
{
    auto ranges = List!HttpRange.of(HttpRange.createByteRange(0, 499),
            HttpRange.createByteRange(9_500), HttpRange.createSuffixRange(500));
    assert(HttpRange.toString(ranges) == "bytes=0-499, 9500-, -500");
}

@("Flint.HttpRange.rangeHeadersAndInvalidSyntax")
unittest
{
    auto request = rangeRequestHeaders();
    assert(request.getFirst(HttpHeaders.RANGE) == "bytes=0-1");
    assert(request.getRange().getFirst() == HttpRange.createByteRange(0, 1));
    request.add(HttpHeaders.RANGE, "bytes=3-4");
    assert(request.getRange().size() == 1);

    request.set(HttpHeaders.RANGE, "invalid");
    request.add(HttpHeaders.IF_RANGE, "\"current\"");
    request.add(HttpHeaders.IF_RANGE, "\"current\"");
    HttpHeaders response;
    response.setETag("\"current\"");
    assert(HttpRange.resolveRanges(request, response).isEmpty());
    rejectsRange(() { request.getRange(); });
    rejectsRange(() { HttpRange.parseRanges("bytes=9223372036854775808-"); });
    rejectsRange(() { HttpRange.parseRanges("bytes=0 - 1"); });
}

@("HttpRangeTests.toResourceRegion")
unittest
{
    auto resource = new ByteArrayResource(cast(immutable(ubyte)[]) "Spring Framework");
    auto region = HttpRange.createByteRange(0, 5).toResourceRegion(resource);
    assert(region.getResource() is resource);
    assert(region.getPosition() == 0);
    assert(region.getCount() == 6);
}

@("HttpRangeTests.toResourceRegionInputStreamResource")
unittest
{
    auto resource = new InputStreamResource(new ByteArrayInputStream([]));
    rejectsRange(() { HttpRange.createByteRange(0, 9).toResourceRegion(resource); });
}

@("HttpRangeTests.toResourceRegionIllegalLength")
unittest
{
    auto resource = new class(cast(immutable(ubyte)[]) "abc") ByteArrayResource
    {
        this(immutable(ubyte)[] bytes)
        {
            super(bytes);
        }

        override long contentLength()
        {
            return -1;
        }
    };
    rejectsRange(() { HttpRange.createByteRange(0, 9).toResourceRegion(resource); });
}

@("HttpRangeTests.toResourceRegionExceptionLength")
unittest
{
    auto resource = new class(new ByteArrayInputStream([])) InputStreamResource
    {
        this(InputStream stream)
        {
            super(stream);
        }

        override long contentLength()
        {
            throw new IOException("length unavailable");
        }
    };
    rejectsRange(() { HttpRange.createByteRange(0, 9).toResourceRegion(resource); });
}

@("HttpRangeTests.toResourceRegionStartingAtResourceByteCount")
unittest
{
    auto resource = new ByteArrayResource(cast(immutable(ubyte)[]) "Spring Framework");
    auto range = HttpRange.createByteRange(resource.contentLength());
    rejectsRange(() { range.toResourceRegion(resource); });
}

@("HttpRangeTests.toResourceRegionsValidations")
unittest
{
    auto resource = new ByteArrayResource(cast(immutable(ubyte)[]) "12345");
    auto below = HttpRange.parseRanges("bytes=0-1,2-3");
    assert(HttpRange.toResourceRegions(below, resource).size() == 2);
    auto atLength = HttpRange.parseRanges("bytes=0-1,2-4");
    rejectsRange(() { HttpRange.toResourceRegions(atLength, resource); });
}

@("Flint.HttpRange.streamSubclassAndOversizeSum")
unittest
{
    auto source = new ByteArrayInputStream(cast(const(ubyte)[]) "abc");
    auto resource = new class(source) InputStreamResource
    {
        this(InputStream stream)
        {
            super(stream);
        }

        override long contentLength()
        {
            return 3;
        }
    };
    auto region = HttpRange.createByteRange(1, 2).toResourceRegion(resource);
    assert(region.getPosition() == 1 && region.getCount() == 2);
    assert(resource.getInputStream() is source);

    auto large = new class(cast(immutable(ubyte)[]) "a") ByteArrayResource
    {
        this(immutable(ubyte)[] bytes)
        {
            super(bytes);
        }

        override long contentLength()
        {
            return long.max;
        }
    };
    auto ranges = List!HttpRange.of(HttpRange.createByteRange(0), HttpRange.createByteRange(0));
    rejectsRange(() { HttpRange.toResourceRegions(ranges, large); });
}
