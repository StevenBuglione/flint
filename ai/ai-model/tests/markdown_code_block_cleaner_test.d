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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/converter/MarkdownCodeBlockCleanerTest.java
// Modified by the Flint authors.
module markdown_code_block_cleaner_test;

import flint.ai.converter : MarkdownCodeBlockCleaner, ResponseTextCleaner, WhitespaceCleaner;
import std.typecons : Nullable, nullable;

@safe:

@("shouldRemoveMultilineCodeBlockWithLanguageIdentifier")
unittest
{
    auto cleaner = new MarkdownCodeBlockCleaner();
    assert(cleaner.clean(nullable("```json\n{\"key\": \"value\"}\n```")).get() == "{\"key\": \"value\"}");
}

@("shouldRemoveMultilineCodeBlockWithoutLanguageIdentifier")
unittest
{
    auto cleaner = new MarkdownCodeBlockCleaner();
    assert(cleaner.clean(nullable("```\n{\"key\": \"value\"}\n```")).get() == "{\"key\": \"value\"}");
}

@("shouldRemoveSingleLineCodeBlockWithoutLanguageIdentifier")
unittest
{
    auto cleaner = new MarkdownCodeBlockCleaner();
    assert(cleaner.clean(nullable("```{\"key\": \"value\"}```")).get() == "{\"key\": \"value\"}");
}

@("shouldReturnNullForNullInput")
unittest
{
    auto cleaner = new MarkdownCodeBlockCleaner();
    assert(cleaner.clean(Nullable!string.init).isNull);
}

@("shouldReturnEmptyForEmptyInput")
unittest
{
    auto cleaner = new MarkdownCodeBlockCleaner();
    assert(cleaner.clean(nullable("")).get() == "");
}

@("shouldNotModifyTextWithoutCodeBlocks")
unittest
{
    ResponseTextCleaner cleaner = new MarkdownCodeBlockCleaner();
    const string input = "plain text without code blocks";
    assert(cleaner.clean(nullable(input)).get() == input);
}

@("shouldHandleMalformedInput")
unittest
{
    auto cleaner = new MarkdownCodeBlockCleaner();
    assert(cleaner.clean(nullable("")).get() == "");
    assert(cleaner.clean(nullable("`")).get() == "`");
    assert(cleaner.clean(nullable("```")).get() == "```");
    assert(cleaner.clean(nullable("``````")).get() == "``````");
    assert(cleaner.clean(nullable("```````")).get() == "`");
}

@("markdown cleaning handles CRLF and preserves Unicode whitespace inside fences")
unittest
{
    auto cleaner = new MarkdownCodeBlockCleaner();
    assert(cleaner.clean(nullable("  ```json\r\n\u2003x\u2003\r\n```  ")).get() == "\u2003x\u2003");
    assert(cleaner.clean(nullable("```\n```")).get() == "");
}

@("whitespace cleaning follows Java trim and preserves missing versus present empty text")
unittest
{
    ResponseTextCleaner cleaner = new WhitespaceCleaner();
    assert(cleaner.clean(Nullable!string.init).isNull);
    assert(cleaner.clean(nullable("\t\u001f\r ")).get() == "");
    assert(cleaner.clean(nullable(" \t\u2003x\u2003\r\n ")).get() == "\u2003x\u2003");
}
