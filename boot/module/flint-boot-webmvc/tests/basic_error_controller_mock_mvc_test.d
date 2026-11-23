// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/error/BasicErrorControllerMockMvcTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `@SpringBootTest` with `MockMvcTester` becomes webmvc_test_support's `MvcFixture`,
// the auto-configured DispatcherServlet whose error dispatch (the test's `ErrorDispatcher`) replays the request at
// `/error` with the status attribute; `spring.web.error.include-message=always` is a `flint.web.*` entry; the
// `error` View bean is an `AbstractView` writing `ERROR_BEAN`.
module basic_error_controller_mock_mvc_test;

import flint.engine.aot.any : Any;
import flint.http : HttpStatus;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.java.lang : IllegalStateException, RuntimeException;
import flint.java.util : HashMap, LinkedHashMap, Map;
import flint.validation : MapBindingResult;
import flint.web.bind : MethodArgumentNotValidException;
import flint.web.bind.annotation : RequestMapping, ResponseStatus, RestController;
import flint.web.servlet : View;
import std.algorithm.searching : canFind;
import webmvc_test_support : MvcFixture, controllerRegistry, mvcFixture;

@safe:

private enum ResponseStatus notFound = ResponseStatus(HttpStatus.NOT_FOUND, HttpStatus.NOT_FOUND);
private enum ResponseStatus noContent = ResponseStatus(HttpStatus.NO_CONTENT, HttpStatus.NO_CONTENT);

/// `@ResponseStatus(HttpStatus.NOT_FOUND)`.
@notFound class NotFoundException : RuntimeException
{
    /// With `message`.
    this(string message) pure nothrow
    {
        super(message);
    }
}

/// `@ResponseStatus(HttpStatus.NO_CONTENT)`.
@noContent class NoContentException : RuntimeException
{
    /// With `message`.
    this(string message) pure nothrow
    {
        super(message);
    }
}

/// The test configuration's `Errors` controller.
@RestController class MockMvcErrors
{
    /// Fails.
    @RequestMapping("/") string home()
    {
        throw new IllegalStateException("Expected!");
    }

    /// Fails with a 404.
    @RequestMapping("/bang") string bang()
    {
        throw new NotFoundException("Expected!");
    }

    /// Fails binding `foo`.
    @RequestMapping("/bind") string bind()
    {
        Map!(string, Any) target = new HashMap!(string, Any);
        target.put("foo", Any.of("foo"));
        auto error = new MapBindingResult(target, "test");
        error.rejectValue("foo", "bar.error");
        throw new MethodArgumentNotValidException(null, error);
    }

    /// Fails with a 204.
    @RequestMapping("/noContent") void noContentHandler()
    {
        throw new NoContentException("Expected!");
    }

    /// `foo`.
    string getFoo()
    {
        return "foo";
    }
}

// The `error` View bean: writes ERROR_BEAN.
private final class ErrorBeanView : View
{
    string getContentType()
    {
        return "text/html";
    }

    void render(LinkedHashMap!(string, Any), HttpServletRequest, HttpServletResponse response)
    {
        response.getWriter().write("ERROR_BEAN");
    }
}

private alias registry = controllerRegistry!(MockMvcErrors, "mockMvcErrors", NotFoundException, NoContentException);

private MvcFixture setup()
{
    Object[string] beans;
    beans["mockMvcErrors"] = new MockMvcErrors;
    beans["error"] = new ErrorBeanView;
    return mvcFixture(&registry, [["flint.web.error.include-message", "always"]], beans);
}

@("BasicErrorControllerMockMvcTests.testDirectAccessForMachineClient") unittest
{
    auto response = setup().perform("GET", "/error");
    assert(response.getStatus() >= 500 && response.getStatus() < 600);
    assert(response.getContentAsString().canFind("999"), response.getContentAsString());
}

@("BasicErrorControllerMockMvcTests.testErrorWithNotFoundResponseStatus") unittest
{
    auto response = setup().perform("GET", "/bang");
    assert(response.getStatus() == 404);
    assert(response.getContentAsString().canFind("Expected!"), response.getContentAsString());
}

@("BasicErrorControllerMockMvcTests.testErrorWithNoContentResponseStatus") unittest
{
    auto response = setup().perform("GET", "/noContent", null, "some/thing");
    assert(response.getStatus() == 204, imported!"std.conv".to!string(response.getStatus()));
    assert(response.getContentAsString().length == 0, response.getContentAsString());
}

// Boot's DefaultErrorAttributes takes the message of a BindingResult error ("Validation failed for object=...");
// Flint's keeps the forwarded "Invalid request content.".
@("BasicErrorControllerMockMvcTests.testBindingExceptionForMachineClient") unittest
{
    auto response = setup().perform("GET", "/bind");
    assert(response.getStatus() >= 400 && response.getStatus() < 500);
    assert(response.getContentAsString().canFind("Validation failed"), response.getContentAsString());
}

@("BasicErrorControllerMockMvcTests.testDirectAccessForBrowserClient") unittest
{
    auto response = setup().perform("GET", "/error", null, "text/html");
    assert(response.getStatus() >= 500 && response.getStatus() < 600);
    assert(response.getContentAsString().canFind("ERROR_BEAN"), response.getContentAsString());
}
