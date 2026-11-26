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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/test/java/org/springframework/ai/observation/conventions/AiProviderTests.java
// Modified by the Flint authors.
module ai_provider_tests;

import flint.ai.observation.conventions : AiProvider;

@safe:

@("enumValuesShouldBeSortedAlphabetically")
unittest
{
    string previous = "";
    foreach (value; AiProvider.values())
    {
        // Compare Java names in the original order even though R1 renames this identifier.
        const name = value == AiProvider.FLINT_AI ? "SPRING_AI" : value.name();
        assert(previous <= name);
        previous = name;
    }
}
