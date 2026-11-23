// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/error/DefaultErrorAttributesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the test methods error_test.d does not port (it holds includeTimeStamp,
// specificStatusCode, missingStatusCode and shouldIncludePathByDefault); `exception` is the D class name; Java's
// `OutOfMemoryError` is a D `Error` subclass; the `BindingResult` and method-validation cases wait behind
// FlintErrorAttributesBindingErrors.
module default_error_attributes_upstream_test;

import flint.boot.web.error : ErrorAttributeOptions;
import flint.boot.webmvc.error : DefaultErrorAttributes;
import flint.engine.aot.any : Any;
import flint.jakarta.servlet : RequestDispatcher, ServletException;
import flint.java.lang : RuntimeException;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.web.context.request : ServletWebRequest, WebRequest;
import std.algorithm.searching : startsWith;

@safe:

private alias Include = ErrorAttributeOptions.Include;

private struct Fixture
{
    DefaultErrorAttributes errorAttributes;
    MockHttpServletRequest request;
    WebRequest webRequest;
}

private Fixture fixture()
{
    auto request = new MockHttpServletRequest;
    return Fixture(new DefaultErrorAttributes, request, new ServletWebRequest(request));
}

private void setException(MockHttpServletRequest request, Throwable ex)
{
    request.setAttribute(RequestDispatcher.ERROR_EXCEPTION, Any.of(cast(Object) ex));
}

@("DefaultErrorAttributesTests.mvcError") unittest
{
    auto f = fixture();
    auto ex = new RuntimeException("Test");
    const modelAndView = f.errorAttributes.resolveException(f.request, new MockHttpServletResponse, null, ex);
    setException(f.request, new RuntimeException("Ignored"));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.MESSAGE));
    assert(f.errorAttributes.getError(f.webRequest) is ex);
    assert(modelAndView is null);
    assert(!attributes.containsKey("exception"));
    assert(attributes.get("message").get!string == "Test");
}

@("DefaultErrorAttributesTests.servletErrorWithMessage") unittest
{
    auto f = fixture();
    auto ex = new RuntimeException("Test");
    setException(f.request, ex);
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.MESSAGE));
    assert(f.errorAttributes.getError(f.webRequest) is ex);
    assert(!attributes.containsKey("exception"));
    assert(attributes.get("message").get!string == "Test");
}

@("DefaultErrorAttributesTests.servletErrorWithoutMessage") unittest
{
    auto f = fixture();
    auto ex = new RuntimeException("Test");
    setException(f.request, ex);
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.defaults());
    assert(f.errorAttributes.getError(f.webRequest) is ex);
    assert(!attributes.containsKey("exception"));
    assert(!attributes.containsKey("message"));
}

@("DefaultErrorAttributesTests.servletMessageWithMessage") unittest
{
    auto f = fixture();
    f.request.setAttribute(RequestDispatcher.ERROR_MESSAGE, Any.of("Test"));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.MESSAGE));
    assert(!attributes.containsKey("exception"));
    assert(attributes.get("message").get!string == "Test");
}

@("DefaultErrorAttributesTests.servletMessageWithoutMessage") unittest
{
    auto f = fixture();
    f.request.setAttribute(RequestDispatcher.ERROR_MESSAGE, Any.of("Test"));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.defaults());
    assert(!attributes.containsKey("exception"));
    assert(!attributes.containsKey("message"));
}

@("DefaultErrorAttributesTests.nullExceptionMessage") unittest
{
    auto f = fixture();
    setException(f.request, new RuntimeException);
    f.request.setAttribute(RequestDispatcher.ERROR_MESSAGE, Any.of("Test"));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.MESSAGE));
    assert(!attributes.containsKey("exception"));
    assert(attributes.get("message").get!string == "Test");
}

@("DefaultErrorAttributesTests.nullExceptionMessageAndServletMessage") unittest
{
    auto f = fixture();
    setException(f.request, new RuntimeException);
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.MESSAGE));
    assert(!attributes.containsKey("exception"));
    assert(attributes.get("message").get!string == "No message available");
}

@("DefaultErrorAttributesTests.unwrapServletException") unittest
{
    auto f = fixture();
    auto ex = new RuntimeException("Test");
    auto wrapped = new ServletException(new ServletException(ex));
    setException(f.request, wrapped);
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.MESSAGE));
    assert(f.errorAttributes.getError(f.webRequest) is wrapped);
    assert(!attributes.containsKey("exception"));
    assert(attributes.get("message").get!string == "Test", attributes.get("message").get!string);
}

// Java's `OutOfMemoryError("Test error")`: an `Error` carrying a message.
private final class TestOutOfMemoryError : Error
{
    this(string message) pure nothrow @nogc
    {
        super(message);
    }
}

@("DefaultErrorAttributesTests.getError") unittest
{
    auto f = fixture();
    Throwable error = new TestOutOfMemoryError("Test error");
    setException(f.request, error);
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.MESSAGE));
    assert(f.errorAttributes.getError(f.webRequest) is error);
    assert(!attributes.containsKey("exception"));
    assert(attributes.get("message").get!string == "Test error");
}

// Boot's DefaultErrorAttributes reads a BindingResult (or a MethodValidationResult) from the error: its errors as
// `errors` and "Validation failed for object='...'. Error count: n" as `message`.
version (FlintErrorAttributesBindingErrors)
{
    import flint.java.util : Collections, List;
    import flint.validation : BindException, BindingResult, MapBindingResult, ObjectError;

    private void testErrors(Fixture f, List!ObjectError errors, string expectedMessage, Exception ex,
            ErrorAttributeOptions options)
    {
        import flint.boot.web.error : Error_ = Error;

        setException(f.request, ex);
        auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, options);
        if (options.isIncluded(Include.MESSAGE))
            assert(attributes.get("message").get!string == expectedMessage);
        else
            assert(!attributes.containsKey("message"));
        if (options.isIncluded(Include.BINDING_ERRORS))
            assert(attributes.get("errors") == Any.of(Error_.wrapIfNecessary(errors)));
        else
            assert(!attributes.containsKey("errors"));
    }

    private void testBindingResult(Fixture f, BindingResult bindingResult, Exception ex, ErrorAttributeOptions options)
    {
        testErrors(f, bindingResult.getAllErrors(),
                "Validation failed for object='objectName'. Error count: 1", ex, options);
    }

    private BindingResult bindingResult()
    {
        auto result = new MapBindingResult(Collections.singletonMap("a", Any.of("b")), "objectName");
        result.addError(new ObjectError("c", "d"));
        return result;
    }

    @("DefaultErrorAttributesTests.withBindingErrors") unittest
    {
        auto result = bindingResult();
        testBindingResult(fixture(), result, new BindException(result),
                ErrorAttributeOptions.of(Include.MESSAGE, Include.BINDING_ERRORS));
    }

    @("DefaultErrorAttributesTests.withoutBindingErrors") unittest
    {
        auto result = bindingResult();
        testBindingResult(fixture(), result, new BindException(result), ErrorAttributeOptions.defaults());
    }

    @("DefaultErrorAttributesTests.withMethodArgumentNotValidExceptionBindingErrors") unittest
    {
        import flint.web.bind : MethodArgumentNotValidException;

        auto result = bindingResult();
        testBindingResult(fixture(), result, new MethodArgumentNotValidException(null, result),
                ErrorAttributeOptions.of(Include.MESSAGE, Include.BINDING_ERRORS));
    }

    @("DefaultErrorAttributesTests.withHandlerMethodValidationExceptionBindingErrors") unittest
    {
        import flint.validation.method : MethodValidationResult, ParameterValidationResult;
        import flint.web.method.annotation : HandlerMethodValidationException;

        auto methodValidationResult = MethodValidationResult.create(Any.of("test"), "substring",
                [
                    new ParameterValidationResult(null, -1, [
                        new ObjectError("beginIndex", "beginIndex is negative")
                    ])
        ]);
        auto ex = new HandlerMethodValidationException(methodValidationResult);
        testErrors(fixture(), methodValidationResult.getAllErrors(),
                "Validation failed for method='public java.lang.String java.lang.String.substring(int)'. "
                ~ "Error count: 1",
                ex, ErrorAttributeOptions.of(Include.MESSAGE, Include.BINDING_ERRORS));
    }
}

@("DefaultErrorAttributesTests.withExceptionAttribute") unittest
{
    auto f = fixture();
    auto errorAttributes = new DefaultErrorAttributes;
    setException(f.request, new RuntimeException("Test"));
    auto attributes = errorAttributes.getErrorAttributes(f.webRequest,
            ErrorAttributeOptions.of(Include.EXCEPTION, Include.MESSAGE));
    assert(attributes.get("exception").get!string == typeid(RuntimeException).name);
    assert(attributes.get("message").get!string == "Test");
}

@("DefaultErrorAttributesTests.withStackTraceAttribute") unittest
{
    auto f = fixture();
    setException(f.request, new RuntimeException("Test"));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.STACK_TRACE));
    auto trace = attributes.get("trace");
    assert(!trace.isNull());
    assert(trace.get!string.startsWith("flint.java.lang"), trace.get!string);
}

@("DefaultErrorAttributesTests.withoutStackTraceAttribute") unittest
{
    auto f = fixture();
    setException(f.request, new RuntimeException("Test"));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.defaults());
    assert(!attributes.containsKey("trace"));
}

@("DefaultErrorAttributesTests.shouldIncludePath") unittest
{
    auto f = fixture();
    f.request.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of("path"));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of(Include.PATH));
    assert(attributes.get("path").get!string == "path");
}

@("DefaultErrorAttributesTests.shouldExcludePath") unittest
{
    auto f = fixture();
    f.request.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of("path"));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest, ErrorAttributeOptions.of());
    assert(!attributes.containsKey("path"));
}

// `getMessage` overridden.
private final class CustomMessageErrorAttributes : DefaultErrorAttributes
{
    protected override string getMessage(WebRequest webRequest, Throwable error)
    {
        return "custom message";
    }
}

@("DefaultErrorAttributesTests.whenGetMessageIsOverriddenThenMessageAttributeContainsValueReturnedFromIt") unittest
{
    auto f = fixture();
    auto attributes = new CustomMessageErrorAttributes().getErrorAttributes(f.webRequest,
            ErrorAttributeOptions.of(Include.MESSAGE));
    assert(attributes.get("message").get!string == "custom message");
}

@("DefaultErrorAttributesTests.excludeStatus") unittest
{
    auto f = fixture();
    f.request.setAttribute(RequestDispatcher.ERROR_STATUS_CODE, Any.of(404));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest,
            ErrorAttributeOptions.defaults().excluding(Include.STATUS));
    assert(!attributes.containsKey("status"));
}

@("DefaultErrorAttributesTests.excludeError") unittest
{
    auto f = fixture();
    f.request.setAttribute(RequestDispatcher.ERROR_STATUS_CODE, Any.of(404));
    auto attributes = f.errorAttributes.getErrorAttributes(f.webRequest,
            ErrorAttributeOptions.defaults().excluding(Include.ERROR));
    assert(!attributes.containsKey("error"));
}
