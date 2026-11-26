module flint.test.web.web_utils_servlet_tests;

import flint.engine.aot.any : Any;
import flint.java.io : File;
import flint.java.lang : ClassCastException, IllegalArgumentException;
import flint.mock.web : MockHttpServletRequest, MockServletContext;
import flint.web.util : WebUtils;
import std.exception : assertThrown;

@safe:

@("Flint.WebUtils.tempDirectoryUsesServletContextAttribute")
unittest
{
    auto context = new MockServletContext();
    assert(WebUtils.getTempDir(context) is null);
    assertThrown!IllegalArgumentException(WebUtils.getTempDir(null));

    auto directory = new File("container-tmp");
    context.setAttribute("jakarta.servlet.context.tempdir", Any.of(cast(Object) directory));
    assert(WebUtils.getTempDir(context) is directory);

    context.setAttribute(WebUtils.TEMP_DIR_CONTEXT_ATTRIBUTE, Any.of("container-tmp"));
    assertThrown!ClassCastException(WebUtils.getTempDir(context));
}

@("Flint.WebUtils.servletSubmitParameters")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addParameter("submit.y", "10");
    request.addParameter("choice_next.x", "20");
    request.addParameter("action", "", "second");
    request.addParameter("action_other", "30");

    assert(WebUtils.hasSubmitParameter(request, "submit"));
    assert(WebUtils.hasSubmitParameter(request, "action"));
    assert(!WebUtils.hasSubmitParameter(request, "choice"));
    assert(!WebUtils.hasSubmitParameter(request, "missing"));
    assert(WebUtils.findParameterValue(request, "choice").get == "next");
    const direct = WebUtils.findParameterValue(request, "action");
    assert(!direct.isNull && direct.get.length == 0);
    assert(WebUtils.findParameterValue(request, "missing").isNull);
}
