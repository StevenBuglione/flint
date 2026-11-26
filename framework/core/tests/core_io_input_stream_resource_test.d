/*
 * Copyright 2002-present the original author or authors.
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
// Ported from spring-framework v7.1.0, spring-core/src/test/java/org/springframework/core/io/ResourceTests.java
// Modified by the Flint authors.

module core_io_input_stream_resource_test;

import flint.core.io : InputStreamResource, InputStreamSource, Resource;
import flint.java.io : ByteArrayInputStream, IOException, InputStream;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import std.exception : assertThrown;

@safe:

private enum bytes = cast(immutable(ubyte)[]) "testString";

@("ResourceTests.InputStreamResourceTests.hasContent")
unittest
{
    auto stream = new ByteArrayInputStream(bytes);
    Resource direct = new InputStreamResource(stream);
    assert(direct.getInputStream().readAllBytes() == bytes);
    auto same = new InputStreamResource(stream);
    assert(same.equals(cast(Object) direct));
    assert(same.hashCode() == (cast(InputStreamResource) direct).hashCode());
    assert(!new InputStreamResource(() => stream).equals(cast(Object) direct));
    assertThrown!IllegalStateException(direct.getInputStream());

    Resource binary = new InputStreamResource(new ByteArrayInputStream(bytes));
    assert(binary.getContentAsByteArray() == bytes);
    assertThrown!IllegalStateException(binary.getContentAsByteArray());

    int calls;
    Resource onDemand = new InputStreamResource(() { ++calls; return new ByteArrayInputStream(bytes); });
    assert(calls == 0);
    assert(onDemand.getContentAsString() == "testString");
    assert(calls == 1);
    assertThrown!IllegalStateException(onDemand.getContentAsString());
    assert(calls == 1);
}

@("ResourceTests.InputStreamResourceTests.isOpen")
unittest
{
    auto stream = new ByteArrayInputStream(bytes);
    Resource direct = new InputStreamResource(stream);
    Resource onDemand = new InputStreamResource(() => stream);
    assert(direct.exists() && direct.isOpen());
    assert(onDemand.exists() && onDemand.isOpen());
}

@("ResourceTests.InputStreamResourceTests.hasDescription")
unittest
{
    auto stream = new ByteArrayInputStream(bytes);
    Resource direct = new InputStreamResource(stream, "my description");
    Resource onDemand = new InputStreamResource(() => stream, "my description");
    assert(direct.getDescription() == "InputStream resource [my description]");
    assert(onDemand.getDescription() == direct.getDescription());
    assert(new InputStreamResource(stream, null).getDescription() == "InputStream resource []");
}

@("the first attempt consumes an on-demand resource even when opening fails")
unittest
{
    InputStreamSource source = new class InputStreamSource
    {
        InputStream getInputStream()
        {
            throw new IOException("cannot open");
        }
    };
    auto resource = new InputStreamResource(source);
    assert(resource.equals(new InputStreamResource(source)));
    assertThrown!IOException(resource.getInputStream());
    assertThrown!IllegalStateException(resource.getInputStream());
}

@("null input streams and sources are rejected")
unittest
{
    assertThrown!IllegalArgumentException(new InputStreamResource(cast(InputStream) null));
    assertThrown!IllegalArgumentException(new InputStreamResource(cast(InputStreamSource) null));
}

@("the same delegate gives equal resources")
unittest
{
    auto stream = new ByteArrayInputStream(bytes);
    InputStream delegate() @safe open = () => stream;
    auto first = new InputStreamResource(open);
    auto second = new InputStreamResource(open);
    assert(first.equals(second));
    assert(first.hashCode() == second.hashCode());
    assert(first.contentLength() == bytes.length);
    assertThrown!IllegalStateException(first.getInputStream());
    assert(second.getInputStream() is stream);
}
