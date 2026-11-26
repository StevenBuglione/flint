/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/http/MediaTypeFactoryTests.java.
Copyright 2002-present the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: JUnit and AssertJ assertions become D unittests and asserts.
+/
module flint.http.media_type_factory_tests;

import flint.core.io : FileSystemResource, Resource;
import flint.http : MediaType, MediaTypeFactory;
import core.memory : GC;

@safe:

@("getMediaType")
unittest
{
    assert(MediaTypeFactory.getMediaType("file.xml").get() == MediaType.APPLICATION_XML);
    assert(MediaTypeFactory.getMediaType("file.js").get() == MediaType.parseMediaType("text/javascript"));
    assert(MediaTypeFactory.getMediaType("file.css").get() == MediaType.parseMediaType("text/css"));
    assert(MediaTypeFactory.getMediaType("file.wasm").get() == MediaType.parseMediaType("application/wasm"));
    assert(MediaTypeFactory.getMediaType("file.foobar").isEmpty());
}

@("nullParameter")
unittest
{
    assert(MediaTypeFactory.getMediaType(cast(string) null).isEmpty());
    assert(MediaTypeFactory.getMediaType(cast(Resource) null).isEmpty());
    assert(MediaTypeFactory.getMediaTypes(null).isEmpty());
}

@("Flint: look up the resource filename and preserve media type order for a shared extension")
unittest
{
    auto resource = new FileSystemResource("directory.with.dots/file.SUB");
    auto primary = MediaType.parseMediaType("image/vnd.dvb.subtitle");
    auto secondary = MediaType.parseMediaType("text/vnd.dvb.subtitle");
    assert(MediaTypeFactory.getMediaType(resource).get() == primary);
    assert(MediaTypeFactory.getMediaTypes("file.sUb").toArray() == [primary, secondary]);
    assert(MediaTypeFactory.getMediaType("directory.with.dots/file").isEmpty());
}

@("Flint: canonicalize a Unicode extension as Java Locale.ROOT does")
unittest
{
    auto kml = MediaType.parseMediaType("application/vnd.google-earth.kml+xml");
    assert(MediaTypeFactory.getMediaType("map.KML").get() == kml);
    assert(MediaTypeFactory.getMediaType("icon.İCO").isEmpty());
}

@("Flint: edits to a result list leave the MIME registry intact")
unittest
{
    auto types = MediaTypeFactory.getMediaTypes("file.xml");
    types.set(0, MediaType.IMAGE_GIF);
    assert(types.get(0) == MediaType.IMAGE_GIF);
    assert(MediaTypeFactory.getMediaType("file.xml").get() == MediaType.APPLICATION_XML);
}

@("Flint: first-media-type lookups allocate no GC bytes")
unittest
{
    auto resource = new FileSystemResource("directory/file.XML");
    const before = GC.stats().allocatedInCurrentThread;
    foreach (_; 0 .. 128)
    {
        assert(MediaTypeFactory.getMediaType("file.WASM").get().toString() == "application/wasm");
        assert(MediaTypeFactory.getMediaType(resource).get() == MediaType.APPLICATION_XML);
        assert(MediaTypeFactory.getMediaType("file.foobar").isEmpty());
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}
