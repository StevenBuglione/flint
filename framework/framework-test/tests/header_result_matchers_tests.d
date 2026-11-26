/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/result/HeaderResultMatchersTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors.
+/
module header_result_matchers_tests;

import flint.http : HttpHeaders;
import flint.java.lang : AssertionError, NumberFormatException;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.test.web.servlet : DefaultMvcResult;
import flint.test.web.servlet.result : MockMvcResultMatchers;

@safe:

@("matchDateFormattedWithHttpHeaders")
unittest
{
    enum epochMillis = 1_538_697_600_000L; // 2018-10-05T00:00:00Z
    auto headers = HttpHeaders.create();
    headers.setDate("myDate", epochMillis);

    auto response = new MockHttpServletResponse;
    response.setHeader("d", headers.getFirst("myDate"));
    auto result = new DefaultMvcResult(new MockHttpServletRequest, response);
    auto matchers = MockMvcResultMatchers.header();
    matchers.dateValue("d", epochMillis).match(result);
    matchers.dateValue("D", epochMillis + 999).match(result);
}

@("MockMvc header date mismatch reports the actual and expected dates")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setHeader("Date", "Fri, 05 Oct 2018 00:00:00 GMT");
    auto result = new DefaultMvcResult(new MockHttpServletRequest, response);
    try
    {
        MockMvcResultMatchers.header().dateValue("Date", 1_538_697_601_000L).match(result);
        assert(false);
    }
    catch (AssertionError failure)
    {
        enum expected = "Response header 'Date'='Fri, 05 Oct 2018 00:00:00 GMT' "
            ~ "does not match expected value 'Fri, 05 Oct 2018 00:00:01 GMT' "
            ~ "expected:<1538697601000> but was:<1538697600000>";
        assert(failure.getMessage() == expected, failure.getMessage());
    }
}

@("MockMvc header errors distinguish missing values from malformed numbers")
unittest
{
    auto response = new MockHttpServletResponse;
    auto result = new DefaultMvcResult(new MockHttpServletRequest, response);
    auto matchers = MockMvcResultMatchers.header();
    try
    {
        matchers.dateValue("Date", 0L).match(result);
        assert(false);
    }
    catch (AssertionError failure)
    {
        assert(failure.getMessage() == "Response does not contain header 'Date'");
    }

    response.setHeader("X-Count", "NaN");
    try
    {
        matchers.longValue("x-count", 0L).match(result);
        assert(false);
    }
    catch (NumberFormatException failure)
    {
        assert(failure.getMessage().length != 0);
    }
}
