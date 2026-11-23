// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/error/DefaultErrorAttributesTests.java
// with ../autoconfigure/error/BasicErrorControllerDirectMockMvcTests.java and DispatcherServletPath's mapping cases.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the controller's methods are called directly with framework-test's mock request
// and response rather than through MockMvc; binding-result and method-validation cases follow with
// flint:validation's BindingResult.
module error_test;

import flint.boot.autoconfigure.web : ErrorProperties;
import flint.boot.web.error : ErrorAttributeOptions;
import flint.boot.webmvc.autoconfigure : DispatcherServletRegistrationBean;
import flint.boot.webmvc.autoconfigure.error : BasicErrorController, WhitelabelErrorView;
import flint.boot.webmvc.error : DefaultErrorAttributes;
import flint.engine.aot.any : Any;
import flint.jakarta.servlet : RequestDispatcher;
import flint.java.time : Instant;
import flint.java.util : LinkedHashMap;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.web.context.request : ServletWebRequest;

@safe:

private alias Include = ErrorAttributeOptions.Include;

private MockHttpServletRequest errorRequest(int status, string uri)
{
    auto request = new MockHttpServletRequest("GET", "/error");
    request.setAttribute(RequestDispatcher.ERROR_STATUS_CODE, Any.of(status));
    request.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of(uri));
    return request;
}

@("includeTimeStamp") unittest
{
    auto attributes = new DefaultErrorAttributes().getErrorAttributes(new ServletWebRequest(errorRequest(404,
            "/x")), ErrorAttributeOptions.defaults());
    assert(attributes.get("timestamp").holds!Instant);
}

@("specificStatusCode") unittest
{
    auto attributes = new DefaultErrorAttributes().getErrorAttributes(new ServletWebRequest(errorRequest(404,
            "/x")), ErrorAttributeOptions.defaults());
    assert(attributes.get("error").get!string == "Not Found");
    assert(attributes.get("status").get!int == 404);
    assert(!attributes.containsKey("message"));
}

@("missingStatusCode") unittest
{
    auto attributes = new DefaultErrorAttributes().getErrorAttributes(new ServletWebRequest(
            new MockHttpServletRequest("GET", "/error")), ErrorAttributeOptions.defaults());
    assert(attributes.get("error").get!string == "None");
    assert(attributes.get("status").get!int == 999);
}

@("defaultKeyOrder: timestamp, status, error, path") unittest
{
    auto attributes = new DefaultErrorAttributes().getErrorAttributes(new ServletWebRequest(errorRequest(404,
            "/nope")), ErrorAttributeOptions.defaults());
    assert(attributes.keySet().toArray() == ["timestamp", "status", "error", "path"]);
    assert(attributes.get("path").get!string == "/nope");
}

@("withoutPath: excluded when the options leave PATH out") unittest
{
    auto attributes = new DefaultErrorAttributes().getErrorAttributes(new ServletWebRequest(errorRequest(404,
            "/x")), ErrorAttributeOptions.defaults().excluding(Include.PATH));
    assert(!attributes.containsKey("path"));
}

@("servletErrorWithMessage and exception: recorded by resolveException, message included on request") unittest
{
    auto errorAttributes = new DefaultErrorAttributes;
    auto request = errorRequest(500, "/x");
    auto exception = new Exception("Test");
    assert(errorAttributes.resolveException(request, new MockHttpServletResponse, null, exception) is null);
    auto webRequest = new ServletWebRequest(request);
    assert(errorAttributes.getError(webRequest) is exception);
    auto attributes = errorAttributes.getErrorAttributes(webRequest,
            ErrorAttributeOptions.of(Include.EXCEPTION, Include.MESSAGE));
    assert(attributes.get("exception").get!string == "object.Exception");
    assert(attributes.get("message").get!string == "Test");
}

@("BasicErrorController.error: the attributes as the body, with the error's status") unittest
{
    auto controller = new BasicErrorController(new DefaultErrorAttributes, new ErrorProperties);
    auto entity = controller.error(errorRequest(405, "/greeting"));
    assert(entity.getStatusCode().value() == 405);
    auto body = entity.getBody().get!(LinkedHashMap!(string, Any));
    assert(body.keySet().toArray() == ["timestamp", "status", "error", "path"]);
    assert(body.get("error").get!string == "Method Not Allowed");
}

@("BasicErrorController.errorHtml: the error view and the status on the response") unittest
{
    auto controller = new BasicErrorController(new DefaultErrorAttributes, new ErrorProperties);
    auto response = new MockHttpServletResponse;
    auto modelAndView = controller.errorHtml(errorRequest(404, "/nope"), response);
    assert(response.getStatus() == 404);
    assert(modelAndView.getViewName() == "error");
    assert(modelAndView.getModel().get("status").get!int == 404);
}

@("the Whitelabel page is Boot's StaticView, with Java's Date text") unittest
{
    auto model = new LinkedHashMap!(string, Any);
    model.put("timestamp", Any.of(Instant.ofEpochSecond(1_795_417_635)));
    model.put("status", Any.of(404));
    model.put("error", Any.of("Not Found"));
    auto response = new MockHttpServletResponse;
    new WhitelabelErrorView().render(model, new MockHttpServletRequest("GET", "/error"), response);
    assert(response.getContentType() == "text/html;charset=UTF-8");
    const html = response.getContentAsString();
    assert(html == "<html><body><h1>Whitelabel Error Page</h1><p>This application has no explicit mapping for "
            ~ "/error, so you are seeing this as a fallback.</p><div id='created'>Mon Nov 23 07:07:15 UTC 2026</div>"
            ~ "<div>There was an unexpected error (type=Not Found, status=404).</div></body></html>", html);
    assert(html.length == 275);
}

@("the Whitelabel page escapes HTML in the message") unittest
{
    auto model = new LinkedHashMap!(string, Any);
    model.put("message", Any.of("<script>&'\""));
    auto response = new MockHttpServletResponse;
    new WhitelabelErrorView().render(model, new MockHttpServletRequest("GET", "/error"), response);
    import std.algorithm.searching : canFind;

    assert(response.getContentAsString().canFind("<div>&lt;script&gt;&amp;&#39;&quot;</div>"));
}

@("DispatcherServletPath.getServletUrlMapping: / and empty map /, a path maps <path>/*") unittest
{
    import flint.web.servlet : DispatcherServlet;

    DispatcherServlet servlet;
    assert(new DispatcherServletRegistrationBean(servlet, "/").getUrlMappings() == ["/"]);
    assert(new DispatcherServletRegistrationBean(servlet, "").getUrlMappings() == ["/"]);
    assert(new DispatcherServletRegistrationBean(servlet, "/spring").getUrlMappings() == [
        "/spring/*"
    ]);
    assert(new DispatcherServletRegistrationBean(servlet, "/spring/").getUrlMappings() == [
        "/spring/*"
    ]);
    assert(new DispatcherServletRegistrationBean(servlet, "/").getServletName() == "dispatcherServlet");
}
