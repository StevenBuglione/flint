// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/test/java/org/springframework/boot/web/server/CompressionTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Tomcat's `Http11NioProtocol.getCompressibleMimeTypes()` default is written out,
// since Flint has no Tomcat.
module compression_test;

import flint.boot.web.server : Compression;

@safe:

// Tomcat 11's `AbstractHttp11Protocol` default compressible MIME types.
private string[] getTomcatDefaultCompressibleMimeTypes()
{
    return [
        "text/html", "text/xml", "text/plain", "text/css", "text/javascript",
        "application/javascript", "application/json", "application/xml"
    ];
}

@("CompressionTests.defaultCompressibleMimeTypesMatchesTomcatsDefault") unittest
{
    import std.algorithm.sorting : sort;

    auto actual = new Compression().getMimeTypes().dup;
    auto expected = getTomcatDefaultCompressibleMimeTypes();
    assert(actual.sort().release == expected.sort().release);
}
