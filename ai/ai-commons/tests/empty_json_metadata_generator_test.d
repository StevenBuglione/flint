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

// Flint's own tests for the ported org.springframework.ai.reader.EmptyJsonMetadataGenerator.
module empty_json_metadata_generator_test;

import flint.ai.reader : EmptyJsonMetadataGenerator, JsonMetadataGenerator;
import flint.engine.aot.any : Any;
import flint.java.lang : UnsupportedOperationException;
import flint.java.util : Map;
import std.exception : assertThrown;

@safe:

private alias JsonFields = Map!(string, Any);

private void assertEmpty(JsonFields metadata)
{
    assert(metadata.isEmpty);
    assert(metadata.size == 0);
}

@("ignores the input fields and returns an empty map")
unittest
{
    JsonMetadataGenerator generator = new EmptyJsonMetadataGenerator();

    assertEmpty(generator.generate(JsonFields.of("title", Any.of("A"), "count", Any.of(3))));
}

@("an empty input map still yields an empty map")
unittest
{
    auto generator = new EmptyJsonMetadataGenerator();

    assertEmpty(generator.generate(JsonFields.of()));
}

@("the returned map is unmodifiable")
unittest
{
    auto generator = new EmptyJsonMetadataGenerator();
    auto metadata = generator.generate(JsonFields.of("title", Any.of("A")));

    assertThrown!UnsupportedOperationException(metadata.put("added", Any.of("value")));
}
