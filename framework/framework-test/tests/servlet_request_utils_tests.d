/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/bind/ServletRequestUtilsTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: JUnit assertions become D assertions and nullable results use R5.
+/
module flint.test.web.servlet_request_utils_tests;

import flint.mock.web : MockHttpServletRequest;
import flint.web.bind : MissingServletRequestParameterException, ServletRequestBindingException, ServletRequestUtils;
import std.exception : assertThrown;

@safe:

private alias Params = ServletRequestUtils;

@("ServletRequestUtilsTests.intParameter")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("param1", "5");
    request.addParameter("param2", "e");
    request.addParameter("paramEmpty", "");

    assert(Params.getIntParameter(request, "param1").get() == 5);
    assert(Params.getIntParameter(request, "param1", 6) == 5);
    assert(Params.getRequiredIntParameter(request, "param1") == 5);
    assert(Params.getIntParameter(request, "param2", 6) == 6);
    assertThrown!ServletRequestBindingException(Params.getRequiredIntParameter(request, "param2"));
    assert(Params.getIntParameter(request, "param3").isNull);
    assert(Params.getIntParameter(request, "param3", 6) == 6);
    assertThrown!MissingServletRequestParameterException(Params.getRequiredIntParameter(request, "param3"));
    assertThrown!ServletRequestBindingException(Params.getRequiredIntParameter(request, "paramEmpty"));
}

@("ServletRequestUtilsTests.intParameters")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("param", "1", "2", "3");
    request.addParameter("param2", "1");
    request.addParameter("param2", "2");
    request.addParameter("param2", "bogus");

    assert(Params.getRequiredIntParameters(request, "param") == [1, 2, 3]);
    assert(Params.getIntParameters(request, "param") == [1, 2, 3]);
    assertThrown!ServletRequestBindingException(Params.getRequiredIntParameters(request, "param2"));
    assert(Params.getIntParameters(request, "param2").length == 0);
}

@("ServletRequestUtilsTests.longParameter")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("param1", "5");
    request.addParameter("param2", "e");
    request.addParameter("paramEmpty", "");

    assert(Params.getLongParameter(request, "param1").get() == 5);
    assert(Params.getLongParameter(request, "param1", 6L) == 5);
    assert(Params.getRequiredIntParameter(request, "param1") == 5);
    assert(Params.getLongParameter(request, "param2", 6L) == 6);
    assertThrown!ServletRequestBindingException(Params.getRequiredLongParameter(request, "param2"));
    assert(Params.getLongParameter(request, "param3").isNull);
    assert(Params.getLongParameter(request, "param3", 6L) == 6);
    assertThrown!MissingServletRequestParameterException(Params.getRequiredLongParameter(request, "param3"));
    assertThrown!ServletRequestBindingException(Params.getRequiredLongParameter(request, "paramEmpty"));
}

@("ServletRequestUtilsTests.longParameters")
unittest
{
    auto request = new MockHttpServletRequest();
    request.setParameter("param", "1", "2", "3");
    request.setParameter("param2", "0");
    request.setParameter("param2", "1");
    request.addParameter("param2", "2");
    request.addParameter("param2", "bogus");

    assert(Params.getRequiredLongParameters(request, "param") == [1L, 2, 3]);
    assert(Params.getLongParameters(request, "param") == [1L, 2, 3]);
    assertThrown!ServletRequestBindingException(Params.getRequiredLongParameters(request, "param2"));
    request.setParameter("param2", "1", "2");
    assert(Params.getRequiredLongParameters(request, "param2") == [1L, 2]);
    request.setParameter("param2");
    assertThrown!MissingServletRequestParameterException(Params.getRequiredLongParameters(request, "param2"));
}

@("ServletRequestUtilsTests.booleanParameter")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("param1", "true");
    request.addParameter("param2", "e");
    request.addParameter("param4", "yes");
    request.addParameter("param5", "1");
    request.addParameter("paramEmpty", "");

    assert(Params.getBooleanParameter(request, "param1").get());
    assert(Params.getBooleanParameter(request, "param1", false));
    assert(Params.getRequiredBooleanParameter(request, "param1"));
    assert(!Params.getBooleanParameter(request, "param2", true));
    assert(!Params.getRequiredBooleanParameter(request, "param2"));
    assert(Params.getBooleanParameter(request, "param3").isNull);
    assert(Params.getBooleanParameter(request, "param3", true));
    assertThrown!MissingServletRequestParameterException(Params.getRequiredBooleanParameter(request, "param3"));
    assert(Params.getBooleanParameter(request, "param4", false));
    assert(Params.getRequiredBooleanParameter(request, "param4"));
    assert(Params.getBooleanParameter(request, "param5", false));
    assert(Params.getRequiredBooleanParameter(request, "param5"));
    assert(!Params.getRequiredBooleanParameter(request, "paramEmpty"));
}

@("ServletRequestUtilsTests.booleanParameters")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("param", "true", "yes", "off", "1", "bogus");
    request.addParameter("param2", "false");
    request.addParameter("param2", "true");
    request.addParameter("param2", "");

    assert(Params.getRequiredBooleanParameters(request, "param") == [true, true, false, true, false]);
    assert(Params.getRequiredBooleanParameters(request, "param2") == [false, true, false]);
    assert(Params.getBooleanParameters(request, "param2") == [false, true, false]);
    assert(Params.getBooleanParameters(request, "missing").length == 0);
}

@("ServletRequestUtilsTests.stringParameter")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("param1", "str");
    request.addParameter("paramEmpty", "");

    assert(Params.getStringParameter(request, "param1").get() == "str");
    assert(Params.getStringParameter(request, "param1", "string") == "str");
    assert(Params.getRequiredStringParameter(request, "param1") == "str");
    assert(Params.getStringParameter(request, "param3").isNull);
    assert(Params.getStringParameter(request, "param3", "string") == "string");
    assert(Params.getStringParameter(request, "param3", null) is null);
    assertThrown!MissingServletRequestParameterException(Params.getRequiredStringParameter(request, "param3"));
    assert(Params.getStringParameter(request, "paramEmpty").get().length == 0);
    assert(Params.getRequiredStringParameter(request, "paramEmpty").length == 0);
}

@("Flint.ServletRequestUtils.validatesSignedBounds")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("intMin", "-2147483648");
    request.addParameter("intOverflow", "2147483648");
    request.addParameter("longMin", "-9223372036854775808");
    request.addParameter("longOverflow", "+9223372036854775808");
    request.addParameter("signed", "+42");
    request.addParameter("untrimmed", " 42");
    assert(Params.getRequiredIntParameter(request, "intMin") == int.min);
    assert(Params.getRequiredLongParameter(request, "longMin") == long.min);
    assert(Params.getRequiredIntParameter(request, "signed") == 42);
    assert(Params.getIntParameter(request, "intOverflow", 7) == 7);
    assert(Params.getLongParameter(request, "longOverflow", 7L) == 7);
    assertThrown!ServletRequestBindingException(Params.getRequiredIntParameter(request, "untrimmed"));
}

@("Flint.ServletRequestUtils.validatesMultiValueStrings")
unittest
{
    auto request = new MockHttpServletRequest();
    request.setParameter("present", "", "space");
    request.setParameter("malformed", ["one", cast(string) null]);
    request.addParameter("unicode", "yeſ");
    assert(Params.getRequiredStringParameters(request, "present") == ["", "space"]);
    assert(Params.getStringParameters(request, "present") == ["", "space"]);
    assert(Params.getStringParameters(request, "missing").length == 0);
    assert(Params.getStringParameters(request, "malformed").length == 0);
    assertThrown!MissingServletRequestParameterException(Params.getRequiredStringParameters(request, "malformed"));
    assert(Params.getRequiredBooleanParameter(request, "unicode"));
}

@("Flint.ServletRequestUtils.acceptsJavaDecimalDigits")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("integers", "٤۲", "-２１４７４８３６４８");
    request.addParameter("longMax", "+922337203685477580７");
    request.addParameter("longOverflow", "922337203685477580８");
    request.addParameter("supplementaryDigit", "\U0001D7D3");
    request.addParameter("untrimmed", " ٤٢");

    assert(Params.getIntParameter(request, "integers").get() == 42);
    assert(Params.getRequiredIntParameters(request, "integers") == [42, int.min]);
    assert(Params.getLongParameter(request, "longMax", 0L) == long.max);
    assert(Params.getLongParameter(request, "longOverflow", 0L) == 0);
    assertThrown!ServletRequestBindingException(Params.getRequiredIntParameter(request, "supplementaryDigit"));
    assertThrown!ServletRequestBindingException(Params.getRequiredIntParameter(request, "untrimmed"));
}
