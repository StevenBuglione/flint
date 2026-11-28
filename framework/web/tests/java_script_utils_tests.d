/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/util/JavaScriptUtilsTests.java.
Copyright 2002-present the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: JUnit and AssertJ assertions become D unittests and asserts.
+/
module flint.web.util.java_script_utils_tests;

import flint.web.util : JavaScriptUtils;

@safe:

@("JavaScriptUtilsTests.escape")
unittest
{
    assert(JavaScriptUtils.javaScriptEscape("\"'\\/\t\n\r\f\b\013") == "\\\"\\'\\\\\\/\\t\\n\\n\\f\\b\\v");
}

@("JavaScriptUtilsTests.escapePsLsLineTerminators")
unittest
{
    assert(JavaScriptUtils.javaScriptEscape("\u2028\u2029") == "\\u2028\\u2029");
}

@("JavaScriptUtilsTests.escapeLessThanGreaterThanSigns")
unittest
{
    assert(JavaScriptUtils.javaScriptEscape("<>") == "\\u003C\\u003E");
}

@("JavaScriptUtilsTests.escapeBacktick")
unittest
{
    assert(JavaScriptUtils.javaScriptEscape("`") == "\\u0060");
}

@("JavaScriptUtilsTests.escapeDollar")
unittest
{
    assert(JavaScriptUtils.javaScriptEscape("$") == "\\u0024");
}

@("JavaScriptUtils.javaScriptEscape leaves ordinary text alone")
unittest
{
    assert(JavaScriptUtils.javaScriptEscape(
            "A sentence containing no special characters.") == "A sentence containing no special characters.");
    assert(JavaScriptUtils.javaScriptEscape("") == "");
}
