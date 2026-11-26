// Ported from Thymeleaf 3.1.7.RELEASE:
// tests/thymeleaf-tests-core/src/test/resources/templateengine/features/text/text01.thtest
// Copyright (c) 2011-2026 Thymeleaf (http://www.thymeleaf.org)
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors.
module flint_tool.engine.aot_thymeleaf_test;

import flint_tool.engine.aot.thymeleaf : ThymeleafError, lowerThymeleaf;

@safe:

@("text01 lowers the entire old element body to an escaped interpolation") unittest
{
    string lowered;
    ThymeleafError error;
    const source = "<div th:text=\"${applicationName}\">\n  Some text\n</div>";
    assert(lowerThymeleaf(source, lowered, error));
    assert(lowered == "<div>{{model.applicationName}}</div>");
    assert(error.message is null);

    assert(lowerThymeleaf(" \r\n<span th:text = '${text_2}'>Old text</span>\n", lowered, error));
    assert(lowered == " \r\n<span>{{model.text_2}}</span>\n");
}

@("unsupported Thymeleaf markup stops compilation before emitting a resource") unittest
{
    string lowered = "previous result";
    ThymeleafError error;
    foreach (source; [
        `<script th:text="${name}">old</script>`, `<div th:utext="${name}">old</div>`,
        `<div th:text="${person.name}">old</div>`,
        `<div th:text="${name}" th:attr="id=${name}">old</div>`,
        `<div th:text="${name}"><span>nested</span></div>`, `<div th:text="${name}">old</span>`,
        `<div th:text="${name}">old</div><p>another element</p>`, `<div th:text="${name}">old`,
        "<div th:text=\"${name}\">\0</div>", "<div th:text=\"${name}\">\xff</div>",
    ])
    {
        assert(!lowerThymeleaf(source, lowered, error), source);
        assert(lowered is null);
        assert(error.code == "FLINT-E1160" && error.message.length != 0);
    }

    assert(!lowerThymeleaf("\n<div th:utext=\"${name}\">old</div>", lowered, error));
    assert(error == ThymeleafError("FLINT-E1160", "expected th:text", 2, 6));
    assert(!lowerThymeleaf(`<script th:text="${name}">old</script>`, lowered, error));
    assert(error == ThymeleafError("FLINT-E1160", "th:text is unsupported on <script>", 1, 2));
}

@("Thymeleaf lowering enforces the template source limit") unittest
{
    enum open = `<p th:text="${name}">`;
    enum close = "</p>";
    auto oldText = new char[1_048_576 - open.length - close.length];
    oldText[] = 'x';

    string lowered;
    ThymeleafError error;
    const source = (open ~ oldText ~ close).idup;
    assert(lowerThymeleaf(source, lowered, error));
    assert(lowered == "<p>{{model.name}}</p>");
    assert(!lowerThymeleaf(source ~ " ", lowered, error));
    assert(lowered is null);
    assert(error == ThymeleafError("FLINT-E1160", "template source exceeds 1 MiB", 1, 1));
}
