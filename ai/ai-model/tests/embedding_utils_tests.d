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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/model/EmbeddingUtilsTests.java
// Modified by the Flint authors.
module embedding_utils_tests;

import flint.ai.model : EmbeddingUtils;

@safe:

@("toFloatArrayShouldConvertCorrectly")
unittest
{
    const result = EmbeddingUtils.toFloatArray([1.0f, 2.0f, 3.0f]);
    assert(result.length == 3);
    assert(result[0].get() == 1.0f && result[1].get() == 2.0f && result[2].get() == 3.0f);
}

@("toFloatArrayShouldReturnEmptyArrayForNullInput")
unittest
{
    const result = EmbeddingUtils.toFloatArray(null);
    assert(result !is null && result.length == 0);
    assert(result !is EmbeddingUtils.toFloatArray(null));
}

@("toFloatArrayShouldReturnEmptyArrayForEmptyInput")
unittest
{
    const empty = (new float[1])[0 .. 0];
    const result = EmbeddingUtils.toFloatArray(empty);
    assert(result !is null && result.length == 0);
}
