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

module json_metadata_generator_contract_tests;

import flint.ai.reader : JsonMetadataGenerator;
import flint.engine.aot.any : Any;
import flint.java.util : HashMap, Map;

@safe:

private alias JsonFields = Map!(string, Any);
private alias MutableJsonFields = HashMap!(string, Any);

private final class CopySelectedFields : JsonMetadataGenerator
{
    override JsonFields generate(JsonFields jsonMap)
    {
        auto metadata = new MutableJsonFields();
        metadata.put("id", jsonMap.get("id"));
        metadata.put("details", jsonMap.get("details"));
        return metadata;
    }
}

@("JSON metadata generators carry scalar and nested values through the typed map")
unittest
{
    JsonFields details = new MutableJsonFields();
    details.put("visible", Any.of(true));
    JsonFields document = new MutableJsonFields();
    document.put("id", Any.of(42));
    document.put("details", Any.of(details));
    document.put("content", Any.of("document text"));

    JsonMetadataGenerator generator = new CopySelectedFields();
    auto metadata = generator.generate(document);
    assert(metadata.size() == 2 && !metadata.containsKey("content"));
    assert(metadata.get("id").get!int() == 42);
    assert(metadata.get("details").get!JsonFields() is details);
    assert(document.size() == 3);
}
