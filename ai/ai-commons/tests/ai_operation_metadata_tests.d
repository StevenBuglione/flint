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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/test/java/org/springframework/ai/observation/AiOperationMetadataTests.java
// Modified by the Flint authors.
module ai_operation_metadata_tests;

import flint.ai.observation : AiOperationMetadata;
import flint.java.lang : IllegalArgumentException;
import std.exception : collectException;

@safe:

private enum operationError = "operationType cannot be null or empty";
private enum providerError = "provider cannot be null or empty";

private void expectInvalid(lazy AiOperationMetadata metadata, string message)
{
    const error = collectException!IllegalArgumentException(metadata);
    assert(error !is null && error.msg == message);
}

@("whenMandatoryMetadataThenReturn")
unittest
{
    const metadata = AiOperationMetadata.builder().operationType("chat").provider("doofenshmirtz").build();
    assert(metadata == AiOperationMetadata("chat", "doofenshmirtz"));
}

@("whenOperationTypeIsNullThenThrow")
unittest
{
    const error = collectException!IllegalArgumentException(AiOperationMetadata.builder()
            .provider("doofenshmirtz").build());
    assert(error !is null && error.msg == operationError);
}

@("whenOperationTypeIsEmptyThenThrow")
unittest
{
    const error = collectException!IllegalArgumentException(AiOperationMetadata.builder()
            .operationType("").provider("doofenshmirtz").build());
    assert(error !is null && error.msg == operationError);
}

@("whenProviderIsNullThenThrow")
unittest
{
    expectInvalid(AiOperationMetadata.builder().operationType("chat").build(), providerError);
}

@("whenProviderIsEmptyThenThrow")
unittest
{
    const error = collectException!IllegalArgumentException(AiOperationMetadata.builder()
            .operationType("chat").provider("").build());
    assert(error !is null && error.msg == providerError);
}

@("whenOperationTypeIsBlankThenThrow")
unittest
{
    const error = collectException!IllegalArgumentException(AiOperationMetadata.builder()
            .operationType("   ").provider("doofenshmirtz").build());
    assert(error !is null && error.msg == operationError);
}

@("whenProviderIsBlankThenThrow")
unittest
{
    const error = collectException!IllegalArgumentException(AiOperationMetadata.builder()
            .operationType("chat").provider("   ").build());
    assert(error !is null && error.msg == providerError);
}

@("whenBuiltWithValidValuesThenFieldsAreAccessible")
unittest
{
    const metadata = AiOperationMetadata.builder().operationType("chat").provider("openai").build();
    assert(metadata.operationType() == "chat");
    assert(metadata.provider() == "openai");
}

@("constructor checks Java whitespace and validates operation first")
unittest
{
    expectInvalid(AiOperationMetadata("\u2003", null), operationError);
    expectInvalid(AiOperationMetadata("chat", "\u2003"), providerError);
    assert(AiOperationMetadata(" chat ", "\u00a0").operationType() == " chat ");
}

@("builder reuse preserves earlier values and Java record semantics")
unittest
{
    auto builder = AiOperationMetadata.builder();
    auto first = builder.operationType("chat").provider("😀").build();
    const second = builder.provider("other").build();
    assert(first != second);
    auto equal = AiOperationMetadata("chat", "😀");
    assert(first.equals(equal) && first == equal);
    assert(first.toHash() == equal.toHash());
    assert(first.hashCode() == 96_396_555);
    assert(first.toString() == "AiOperationMetadata[operationType=chat, provider=😀]");
}
