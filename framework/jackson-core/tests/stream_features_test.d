/*
 * Ported from Jackson (jackson-core) 3.1.8 tests, https://github.com/FasterXML/jackson-core,
 * tag jackson-core-3.1.8, src/test/java/tools/jackson/core/unittest/json/JsonFactoryTest.java.
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: also verify the configured ordinal masks on streams.
 */
module stream_features_test;

import flint.jackson.core : ObjectWriteContext, StreamReadFeature, StreamWriteFeature;
import flint.jackson.core.json : JsonFactory;
import flint.jackson.core.util : ByteArrayBuilder;

@safe:

@("JsonFactoryTest.testStreamWriteFeatures")
unittest
{
    auto factory = JsonFactory.builder().enable(StreamWriteFeature.IGNORE_UNKNOWN).build();
    assert(factory.isEnabled(StreamWriteFeature.IGNORE_UNKNOWN));
    auto generator = factory.createGenerator(ObjectWriteContext.empty(), new ByteArrayBuilder);
    // The first three bits are enabled by default. IGNORE_UNKNOWN has ordinal four.
    assert(generator.streamWriteFeatures() == 0x17);

    factory = factory.rebuild().configure(StreamWriteFeature.IGNORE_UNKNOWN, false).build();
    assert(!factory.isEnabled(StreamWriteFeature.IGNORE_UNKNOWN));
    auto defaults = factory.createGenerator(ObjectWriteContext.empty(), new ByteArrayBuilder);
    assert(defaults.streamWriteFeatures() == 0x07);
    assert(generator.streamWriteFeatures() == 0x17);
    defaults.close();
    generator.close();
}

@("parser feature masks reflect the factory configuration")
unittest
{
    auto factory = JsonFactory.builder().build();
    auto parser = factory.createParser("42");
    // AUTO_CLOSE_SOURCE, CLEAR_CURRENT_TOKEN_ON_CLOSE and the two fast numeric features.
    assert(parser.streamReadFeatures() == 0x69);

    auto configured = factory.rebuild().disable(StreamReadFeature.AUTO_CLOSE_SOURCE)
        .enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION).build().createParser("42");
    assert(configured.streamReadFeatures() == 0x6c);
    assert(parser.streamReadFeatures() == 0x69);
    configured.close();
    parser.close();
}
