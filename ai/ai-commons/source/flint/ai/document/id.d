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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/document/id/{IdGenerator,RandomIdGenerator}.java
// Modified by the Flint authors.
module flint.ai.document.id;

import flint.engine.aot.any : Any;

@safe:

/// Generates document identifiers from the supplied content.
interface IdGenerator
{
    /// Generates an identifier from the erased content arguments.
    /// Implementations can alias IdGenerator.generateId to expose both overloads on the concrete type.
    string generateId(scope Any[] contents);

    /// Boxes separate content arguments on the stack (R7).
    string generateId(Args...)(Args contents)
    {
        // Even with no arguments, Java supplies a non-null empty array.
        Any[Args.length > 0 ? Args.length : 1] boxed;
        static foreach (i; 0 .. Args.length)
        {
            static if (!is(Args[i] == typeof(null)))
                boxed[i] = Any.of(contents[i]);
        }
        return generateId(boxed[0 .. Args.length]);
    }
}

/// Generates a random UUID for a document.
class RandomIdGenerator : IdGenerator
{
    alias generateId = IdGenerator.generateId;

    /// Creates a random ID generator.
    this() pure nothrow @nogc
    {
    }

    /// Returns a version 4 UUID regardless of the supplied content.
    override string generateId(scope Any[] contents)
    {
        import flint.java.util.uuid : UUID;

        return UUID.randomUUID().toString();
    }
}
