// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/error/ErrorMvcAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's `error` View and `ErrorAttributes` beans are called
// directly, as Flint AOT's generated definitions call them, instead of through a WebApplicationContextRunner; a
// `DispatcherServletWebRequest` is a `ServletWebRequest` over the mock request and response; the stack trace starts
// with the D class name.
module error_mvc_auto_configuration_test;

import flint.boot.autoconfigure.web : WebProperties;
import flint.boot.web.error : ErrorAttributeOptions;
import flint.boot.webmvc.autoconfigure.error : ErrorMvcAutoConfiguration;
import flint.engine.aot.any : Any;
import flint.jakarta.servlet : RequestDispatcher;
import flint.java.lang : IllegalStateException;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.web.context.request : RequestAttributes, ServletWebRequest;
import std.algorithm.searching : canFind;

@safe:

private struct WebRequest
{
    ServletWebRequest webRequest;
    MockHttpServletRequest request;
    MockHttpServletResponse response;
}

private WebRequest createWebRequest(Exception ex, bool committed)
{
    auto request = new MockHttpServletRequest("GET", "/path");
    auto response = new MockHttpServletResponse;
    auto webRequest = new ServletWebRequest(request, response);
    webRequest.setAttribute(RequestDispatcher.ERROR_EXCEPTION, Any.of(cast(Object) ex),
            RequestAttributes.SCOPE_REQUEST);
    webRequest.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of("/path"), RequestAttributes.SCOPE_REQUEST);
    response.setCommitted(committed);
    return WebRequest(webRequest, request, response);
}

private ErrorAttributeOptions withAllOptions()
{
    import std.traits : EnumMembers;

    return ErrorAttributeOptions.of([EnumMembers!(ErrorAttributeOptions.Include)]);
}

private ErrorMvcAutoConfiguration configuration()
{
    return new ErrorMvcAutoConfiguration(new WebProperties);
}

@("ErrorMvcAutoConfigurationTests.renderContainsViewWithExceptionDetails") unittest
{
    auto errorView = configuration().defaultErrorView();
    auto errorAttributes = configuration().errorAttributes();
    auto web = createWebRequest(new IllegalStateException("Exception message"), false);
    errorView.render(errorAttributes.getErrorAttributes(web.webRequest, withAllOptions()), web.request, web.response);
    assert(web.response.getContentType() == "text/html;charset=UTF-8");
    const responseString = web.response.getContentAsString();
    assert(responseString.canFind(
            "<p>This application has no explicit mapping for /error, so you are seeing this as a fallback.</p>"));
    assert(responseString.canFind("<div>Exception message</div>"));
    assert(responseString.canFind("<div style='white-space:pre-wrap;'>" ~ typeid(IllegalStateException)
            .name), responseString);
}

@("ErrorMvcAutoConfigurationTests.renderCanUseJavaTimeTypeAsTimestamp") unittest
{
    import flint.java.time : Instant;

    auto errorView = configuration().defaultErrorView();
    auto errorAttributes = configuration().errorAttributes();
    auto web = createWebRequest(new IllegalStateException("Exception message"), false);
    auto attributes = errorAttributes.getErrorAttributes(web.webRequest, withAllOptions());
    attributes.put("timestamp", Any.of(Instant.now()));
    errorView.render(attributes, web.request, web.response);
    assert(web.response.getContentType() == "text/html;charset=UTF-8");
    assert(web.response.getContentAsString().canFind("This application has no explicit mapping for /error"));
}

@("ErrorMvcAutoConfigurationTests.renderEscapesHtmlInErrorAttributes") unittest
{
    auto errorView = configuration().defaultErrorView();
    auto errorAttributes = configuration().errorAttributes();
    auto web = createWebRequest(new IllegalStateException("Exception message"), false);
    auto attributes = errorAttributes.getErrorAttributes(web.webRequest, withAllOptions());
    attributes.put("error", Any.of("<script>alert('xss-error')</script>"));
    attributes.put("message", Any.of("<script>alert('xss-message')</script>"));
    attributes.put("timestamp", Any.of("<script>alert('xss-timestamp')</script>"));
    attributes.put("trace", Any.of("<script>alert('xss-trace')</script>"));
    errorView.render(attributes, web.request, web.response);
    const responseString = web.response.getContentAsString();
    assert(responseString.canFind("&lt;script&gt;alert(&#39;xss-error&#39;)&lt;/script&gt;"));
    assert(responseString.canFind("&lt;script&gt;alert(&#39;xss-message&#39;)&lt;/script&gt;"));
    assert(responseString.canFind("&lt;script&gt;alert(&#39;xss-timestamp&#39;)&lt;/script&gt;"));
    assert(responseString.canFind("&lt;script&gt;alert(&#39;xss-trace&#39;)&lt;/script&gt;"));
    assert(!responseString.canFind("<script>"));
}

// Boot's StaticView logs that a committed response cannot carry the error page; Flint's returns silently.
version (FlintWhitelabelCommittedLog)
{
    @("ErrorMvcAutoConfigurationTests.renderWhenAlreadyCommittedLogsMessage") unittest
    {
        import flint.boot.test.system : OutputCapture;

        auto output = new OutputCapture;
        auto errorView = configuration().defaultErrorView();
        auto errorAttributes = configuration().errorAttributes();
        auto web = createWebRequest(new IllegalStateException("Exception message"), true);
        errorView.render(errorAttributes.getErrorAttributes(web.webRequest, withAllOptions()),
                web.request, web.response);
        assert(output.toString()
                .canFind("Cannot render error page for request [/path] and exception [Exception message] "
                    ~ "as the response has "
                    ~ "already been committed. As a result, the response may have the wrong status code."));
    }
}
