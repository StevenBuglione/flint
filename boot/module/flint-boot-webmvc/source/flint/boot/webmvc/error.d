// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/main/java/org/springframework/boot/webmvc/error/DefaultErrorAttributes.java
// with ErrorAttributes.java and ErrorController.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `Map<String, Object>` is `LinkedHashMap!(string, Any)`, the model type of
// flint:webmvc (R12); binding and method-validation results join with flint:validation's `BindingResult`. The
// error's message is read through `getMessage()`, as Java reads it, where the throwable is a Flint exception.

/// `org.springframework.boot.webmvc.error`: error handling for Spring MVC.
module flint.boot.webmvc.error;

import flint.boot.web.error : ErrorAttributeOptions;
import flint.core : Ordered;
import flint.engine.aot.any : Any;
import flint.jakarta.servlet : RequestDispatcher, ServletException;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.java.util : Date, LinkedHashMap;
import flint.web.context.request : RequestAttributes, WebRequest;
import flint.web.servlet : HandlerExceptionResolver, ModelAndView;

@safe:

/// Provides the attributes of an error response, and the error that caused it.
interface ErrorAttributes
{
    /// The error attributes of `webRequest`, as `options` select them.
    LinkedHashMap!(string, Any) getErrorAttributes(WebRequest webRequest, ErrorAttributeOptions options);

    /// The error that caused the request to fail, or `null`.
    Throwable getError(WebRequest webRequest);
}

/// Marks the controller that renders errors.
interface ErrorController
{
}

/// The default `ErrorAttributes`: `timestamp`, `status`, `error`, `exception`, `message`, `trace` and `path`, from
/// the request's `jakarta.servlet.error.*` attributes. It is also the first `HandlerExceptionResolver`, so that it
/// records the exception a handler threw.
class DefaultErrorAttributes : ErrorAttributes, HandlerExceptionResolver, Ordered
{
    private enum string ERROR_INTERNAL_ATTRIBUTE = "flint.boot.webmvc.error.DefaultErrorAttributes.ERROR";

    /// `HIGHEST_PRECEDENCE`.
    int getOrder()
    {
        return Ordered.HIGHEST_PRECEDENCE;
    }

    /// Record `ex` on the request; never handles it.
    ModelAndView resolveException(HttpServletRequest request, HttpServletResponse, Object, Exception ex)
    {
        request.setAttribute(ERROR_INTERNAL_ATTRIBUTE, Any.of(cast(Object) ex));
        return null;
    }

    /// The error attributes, without those `options` leave out.
    LinkedHashMap!(string, Any) getErrorAttributes(WebRequest webRequest, ErrorAttributeOptions options)
    {
        auto errorAttributes = new LinkedHashMap!(string, Any);
        errorAttributes.put("timestamp", Any.of(new Date()));
        addStatus(errorAttributes, webRequest);
        addErrorDetails(errorAttributes, webRequest, options.isIncluded(ErrorAttributeOptions.Include.STACK_TRACE));
        addPath(errorAttributes, webRequest);
        options.retainIncluded(errorAttributes);
        return errorAttributes;
    }

    /// The exception a handler threw, else the servlet engine's `jakarta.servlet.error.exception`, else `null`.
    Throwable getError(WebRequest webRequest)
    {
        if (auto exception = throwableAttribute(webRequest, ERROR_INTERNAL_ATTRIBUTE))
            return exception;
        return throwableAttribute(webRequest, RequestDispatcher.ERROR_EXCEPTION);
    }

    /// The message: `jakarta.servlet.error.message`, else the error's message, else "No message available".
    protected string getMessage(WebRequest webRequest, Throwable error)
    {
        const message = webRequest.getAttribute(RequestDispatcher.ERROR_MESSAGE, RequestAttributes.SCOPE_REQUEST);
        if (!message.isNull() && message.holds!string && message.get!string.length)
            return message.get!string;
        const errorMessage = error is null ? null : messageOf(error);
        if (errorMessage.length)
            return errorMessage.idup;
        return "No message available";
    }

    private void addStatus(LinkedHashMap!(string, Any) errorAttributes, WebRequest webRequest)
    {
        import flint.http : HttpStatus;
        import std.conv : to;

        const status = webRequest.getAttribute(RequestDispatcher.ERROR_STATUS_CODE, RequestAttributes.SCOPE_REQUEST);
        if (status.isNull() || !status.holds!int)
        {
            errorAttributes.put("status", Any.of(999));
            errorAttributes.put("error", Any.of("None"));
            return;
        }
        const code = status.get!int;
        errorAttributes.put("status", Any.of(code));
        try
            errorAttributes.put("error", Any.of(HttpStatus.valueOf(code).getReasonPhrase()));
        catch (Exception)
            errorAttributes.put("error", Any.of("Http Status " ~ code.to!string));
    }

    private void addErrorDetails(LinkedHashMap!(string, Any) errorAttributes, WebRequest webRequest,
            bool includeStackTrace)
    {
        Throwable error = getError(webRequest);
        if (error !is null)
        {
            while (cast(ServletException) error && error.next !is null)
                error = error.next;
            errorAttributes.put("exception", Any.of(typeid(error).name));
            if (includeStackTrace)
                errorAttributes.put("trace", Any.of(stackTraceOf(error)));
        }
        addErrorMessage(errorAttributes, webRequest, error);
    }

    // A BindingResult error gives its own message and errors; Flint has no MethodValidationResult yet.
    private void addErrorMessage(LinkedHashMap!(string, Any) errorAttributes, WebRequest webRequest, Throwable error)
    {
        import flint.boot.web.error : Error_;
        import flint.validation : BindingResult;
        import std.conv : to;

        if (auto result = cast(BindingResult) error)
        {
            auto errors = result.getAllErrors();
            errorAttributes.put("message", Any.of("Validation failed for object='" ~ result.getObjectName()
                    ~ "'. Error count: " ~ errors.size().to!string));
            errorAttributes.put("errors", Any.of(Error_.wrapIfNecessary(errors)));
            return;
        }
        errorAttributes.put("message", Any.of(getMessage(webRequest, error)));
    }

    private void addPath(LinkedHashMap!(string, Any) errorAttributes, WebRequest webRequest)
    {
        const path = webRequest.getAttribute(RequestDispatcher.ERROR_REQUEST_URI, RequestAttributes.SCOPE_REQUEST);
        if (!path.isNull() && path.holds!string)
            errorAttributes.put("path", Any.of(path.get!string));
    }

    private static Throwable throwableAttribute(WebRequest webRequest, string name)
    {
        auto value = webRequest.getAttribute(name, RequestAttributes.SCOPE_REQUEST);
        if (value.isNull() || !value.holds!Object)
            return null;
        return cast(Throwable) value.get!Object;
    }

    private static string stackTraceOf(Throwable error)
    {
        return typeid(error).name ~ ": " ~ messageOf(error).idup ~ "\n\tat " ~ error.file ~ ":" ~ lineOf(error);
    }

    // Java's `Throwable.getMessage()`: a Flint exception's `getMessage`, which a subclass may build on demand, and
    // druntime's message for any other D throwable.
    private static const(char)[] messageOf(Throwable error)
    {
        import flint.java.lang : AssertionError, RuntimeException;

        if (auto runtime = cast(RuntimeException) error)
            return runtime.getMessage();
        if (auto assertion = cast(AssertionError) error)
            return assertion.getMessage();
        return error.message();
    }

    private static string lineOf(Throwable error)
    {
        import std.conv : to;

        return error.line.to!string;
    }
}
