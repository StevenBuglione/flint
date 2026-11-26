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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/test/java/org/springframework/ai/template/NoOpTemplateRendererTests.java
// Modified by the Flint authors.
module no_op_template_renderer_tests;

import flint.ai.template_ : NoOpTemplateRenderer;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : LinkedHashMap, Map;
import flint.java.util.function_ : BiFunction;
import std.exception : collectException;

@safe:

private alias Variables = Map!(string, Any);

private void assertRejected(string text, Variables variables, string message)
{
    const failure = collectException!IllegalArgumentException(new NoOpTemplateRenderer().apply(text, variables));
    assert(failure !is null);
    assert(failure.msg == message);
}

@("shouldReturnUnchangedTemplate")
unittest
{
    BiFunction!(string, Variables, string) renderer = new NoOpTemplateRenderer();
    const result = renderer.apply("Hello {name}!", Variables.of("name", Any.of("Spring AI")));
    assert(result == "Hello {name}!");
}

@("shouldReturnUnchangedTemplateWithMultipleVariables")
unittest
{
    auto variables = Variables.of("greeting", Any.of("Hello"), "name", Any.of("Spring AI"),
            "punctuation", Any.of("!"));
    assert(new NoOpTemplateRenderer().apply("{greeting} {name}{punctuation}",
            variables) == "{greeting} {name}{punctuation}");
}

@("shouldNotAcceptEmptyTemplate")
unittest
{
    assertRejected("", Variables.of(), "template cannot be null or empty");
}

@("shouldNotAcceptNullTemplate")
unittest
{
    assertRejected(null, Variables.of(), "template cannot be null or empty");
}

@("shouldNotAcceptNullVariables")
unittest
{
    assertRejected("Hello!", null, "variables cannot be null");
}

@("shouldNotAcceptVariablesWithNullKeySet")
unittest
{
    auto variables = new LinkedHashMap!(string, Any)();
    variables.put(null, Any.of("Spring AI"));
    assertRejected("Hello!", variables, "variables keys cannot be null");
}

@("shouldReturnUnchangedComplexTemplate")
unittest
{
    enum text = "{header}\nUser: {user}\nItems: {items}\n{footer}\n";
    auto variables = Variables.of("header", Any.of("Welcome"), "user", Any.of("Spring AI"),
            "items", Any.of("one, two, three"), "footer", Any.of("Goodbye"));
    assert(new NoOpTemplateRenderer().apply(text, variables) == text);
}

@("an empty key and null value are allowed")
unittest
{
    auto variables = new LinkedHashMap!(string, Any)();
    variables.put("", Any.init);
    assert(new NoOpTemplateRenderer().apply("  Keep this text  ", variables) == "  Keep this text  ");
}

@("an all-whitespace template is rejected before variables")
unittest
{
    assertRejected(" \t\u2003", null, "template cannot be null or empty");
}
