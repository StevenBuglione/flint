/++
`org.springframework.test.web.servlet.result`: result matchers and handlers.

Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/main/java/org/springframework/test/web/servlet/result/ (MockMvcResultMatchers.java,
StatusResultMatchers.java, ContentResultMatchers.java, HeaderResultMatchers.java, JsonPathResultMatchers.java,
ModelResultMatchers.java, ViewResultMatchers.java, HandlerResultMatchers.java, CookieResultMatchers.java,
MockMvcResultHandlers.java, PrintingResultHandler.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook. Failure messages are Spring's. `jsonPath`'s
`value(Object)` is `value!T(T)` (R4), converting the JSON value to `T` as Spring converts to the expected class.
Hamcrest-matcher overloads are not ported (Hamcrest is a separate library).
+/
module flint.test.web.servlet.result;

import flint.http : HttpHeaders, HttpStatus, MediaType;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : canonicalTypeName, typeNameOf;
import flint.engine.aot.text : decimal;
import flint.jakarta.servlet.http : Cookie;
import flint.java.io : IOException, OutputStream, OutputStreamWriter, Writer;
import flint.java.lang : AssertionError, Boolean, IllegalStateException, Integer, Long,
    NullPointerException, String, valueOf;
import flint.java.nio.charset : Charset;
import flint.test.json : JsonComparator, JsonCompareMode, JsonComparison;
import flint.test.util : AssertionErrors, JsonPathExpectationsHelper;
import flint.test.web.servlet : MvcResult, ResultHandler, ResultMatcher;
import flint.test.web.sys.output : writeStandardOutput;
import flint.util : AntPathMatcher;
import flint.validation : BindingResult, Errors;
import flint.web.method : HandlerMethod;
import flint.web.servlet : ModelAndView;
import flint.web.util : UriComponentsBuilder;
import std.typecons : Nullable;

@safe:

private alias NullableJsonText = Nullable!string;

/// `MockMvcResultMatchers`: static factory methods for matchers.
struct MockMvcResultMatchers
{
    /// Matchers on the response status.
    static StatusResultMatchers status()
    {
        return new StatusResultMatchers;
    }

    /// Matchers on the response body and content type.
    static ContentResultMatchers content()
    {
        return new ContentResultMatchers;
    }

    /// Matchers on response headers.
    static HeaderResultMatchers header()
    {
        return new HeaderResultMatchers;
    }

    /// Matchers on cookies added to the response.
    static CookieResultMatchers cookie()
    {
        return new CookieResultMatchers;
    }

    /// Matchers on the JSON body at `expression`, formatted with Java's format specifiers.
    static JsonPathResultMatchers jsonPath(Args...)(string expression, Args args)
    {
        return new JsonPathResultMatchers(expression, args);
    }

    /// Matchers on model attributes and binding errors.
    static ModelResultMatchers model()
    {
        return new ModelResultMatchers;
    }

    /// Matchers on the selected view.
    static ViewResultMatchers view()
    {
        return new ViewResultMatchers;
    }

    /// Matchers on the handler that served the request.
    static HandlerResultMatchers handler()
    {
        return new HandlerResultMatchers;
    }

    /// Asserts the forwarded URL.
    static ResultMatcher forwardedUrl(string expectedUrl)
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertEquals("Forwarded URL", expectedUrl, cast(string) null);
        });
    }

    /// Asserts the redirected URL.
    static ResultMatcher redirectedUrl(string expectedUrl)
    {
        return redirectedUrl(nullableText(expectedUrl));
    }

    /// A null expected URL asserts that no redirect occurred (R5).
    static ResultMatcher redirectedUrl(Nullable!string expectedUrl)
    {
        return ResultMatcher.of((MvcResult result) {
            assertTextEquals("Redirected URL", expectedUrl, result.getResponse().getRedirectedUrl());
        });
    }

    /// Asserts the expanded and encoded redirect URL.
    static ResultMatcher redirectedUrlTemplate(Args...)(string urlTemplate, Args uriVars)
    {
        string[Args.length] values;
        static foreach (index; 0 .. Args.length)
            values[index] = uriVariableText(uriVars[index]);
        return redirectedUrl(expandUrlTemplate(urlTemplate, values[]));
    }

    /// Asserts the redirect URL against an Ant-style path pattern.
    static ResultMatcher redirectedUrlPattern(string urlPattern)
    {
        auto matcher = new AntPathMatcher;
        matcher.setCachePatterns(false);
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertTrue("'" ~ urlPattern ~ "' is not an Ant-style path pattern",
                matcher.isPattern(urlPattern));
            const url = result.getResponse().getRedirectedUrl();
            AssertionErrors.assertTrue("Redirected URL '" ~ (url is null
                ? "null" : url) ~ "' does not match the expected URL pattern '" ~ urlPattern ~ "'",
                url !is null && matcher.match(urlPattern, url));
        });
    }
}

private string uriVariableText(T)(T value)
{
    static if (is(T == Any))
        return value.isNull() ? null : (value.asObject() is null ? value.toString() : valueOf(value.asObject()));
    else static if (is(T == typeof(null)))
        return null;
    else static if (is(T == class) || is(T == interface) || is(T : const(char)[]))
        return value is null ? null : valueOf(value);
    else
        return valueOf(value);
}

private string expandUrlTemplate(string urlTemplate, scope string[] values)
{
    return UriComponentsBuilder.fromUriString(urlTemplate).buildAndExpand(values).encode().toUriString();
}

private Nullable!string nullableText(string text)
{
    return text is null ? Nullable!string.init : Nullable!string(text);
}

private void assertTextEquals(string message, Nullable!string expected, string actual)
{
    if (expected.isNull ? actual !is null : actual is null || expected.get() != actual)
        AssertionErrors.fail(message, expected.isNull ? "null" : expected.get(), actual is null ? "null" : actual);
}

private void assertCount(string message, int expected, int actual)
{
    if (expected != actual)
        AssertionErrors.fail(message, Integer.toString(expected), Integer.toString(actual));
}

/// `CookieResultMatchers`.
class CookieResultMatchers
{
    /// Obtain the standard instance through `MockMvcResultMatchers.cookie()`.
    protected this() pure nothrow @nogc
    {
    }

    /// Asserts the cookie's value.
    ResultMatcher value(string name, string expectedValue)
    {
        return this.value(name, nullableText(expectedValue));
    }

    /// ditto, distinguishing a missing value from an empty string (R5)
    ResultMatcher value(string name, Nullable!string expectedValue)
    {
        return ResultMatcher.of((MvcResult result) {
            assertTextEquals("Response cookie", expectedValue, requireCookie(result, name).getValue());
        });
    }

    /// Asserts the cookie's path.
    ResultMatcher path(string name, string path)
    {
        return this.path(name, nullableText(path));
    }

    /// ditto, distinguishing a missing value from an empty string (R5)
    ResultMatcher path(string name, Nullable!string path)
    {
        return ResultMatcher.of((MvcResult result) {
            assertTextEquals(cookieLabel(name) ~ " path", path, requireCookie(result, name).getPath());
        });
    }

    /// Asserts the cookie's domain.
    ResultMatcher domain(string name, string domain)
    {
        return this.domain(name, nullableText(domain));
    }

    /// ditto, distinguishing a missing value from an empty string (R5)
    ResultMatcher domain(string name, Nullable!string domain)
    {
        return ResultMatcher.of((MvcResult result) {
            assertTextEquals(cookieLabel(name) ~ " domain", domain, requireCookie(result, name).getDomain());
        });
    }

    /// Asserts the response contains the cookie, including expired cookies.
    ResultMatcher exists(string name)
    {
        return ResultMatcher.of((MvcResult result) { requireCookie(result, name); });
    }

    /// Asserts the response contains no cookie with this name.
    ResultMatcher doesNotExist(string name)
    {
        return ResultMatcher.of((MvcResult result) {
            if (findCookie(result, name) !is null)
                AssertionErrors.fail("Unexpected cookie with name '" ~ name ~ "'");
        });
    }

    /// Asserts the cookie's maximum age in seconds.
    ResultMatcher maxAge(string name, int maxAge)
    {
        return ResultMatcher.of((MvcResult result) {
            assertCount(cookieLabel(name) ~ " maxAge", maxAge, requireCookie(result, name).getMaxAge());
        });
    }

    /// Asserts the cookie's SameSite attribute.
    ResultMatcher sameSite(string name, string sameSite)
    {
        return attribute(name, "SameSite", sameSite);
    }

    /// ditto, with an explicit nullable attribute value (R5)
    ResultMatcher sameSite(string name, Nullable!string sameSite)
    {
        return attribute(name, "SameSite", sameSite);
    }

    /// Asserts whether the cookie is secure.
    ResultMatcher secure(string name, bool secure)
    {
        return ResultMatcher.of((MvcResult result) {
            assertFlag(name, "secure", secure, requireCookie(result, name).getSecure());
        });
    }

    /// Asserts whether the cookie is HTTP-only.
    ResultMatcher httpOnly(string name, bool httpOnly)
    {
        return ResultMatcher.of((MvcResult result) {
            assertFlag(name, "httpOnly", httpOnly, requireCookie(result, name).isHttpOnly());
        });
    }

    /// Asserts whether the Partitioned attribute is present.
    ResultMatcher partitioned(string name, bool partitioned)
    {
        return ResultMatcher.of((MvcResult result) {
            const present = requireCookie(result, name).getAttribute("Partitioned") !is null;
            assertFlag(name, "partitioned", partitioned, present);
        });
    }

    /// Asserts the named cookie attribute's value. Attribute names are case-insensitive.
    ResultMatcher attribute(string cookieName, string cookieAttribute, string attributeValue)
    {
        return attribute(cookieName, cookieAttribute, nullableText(attributeValue));
    }

    /// ditto, distinguishing an absent attribute from an empty value (R5)
    ResultMatcher attribute(string cookieName, string cookieAttribute, Nullable!string attributeValue)
    {
        return ResultMatcher.of((MvcResult result) {
            const actual = requireCookie(result, cookieName).getAttribute(cookieAttribute);
            assertTextEquals(cookieLabel(cookieName) ~ " attribute '" ~ cookieAttribute ~ "'", attributeValue, actual);
        });
    }

    private static string cookieLabel(string name)
    {
        return "Response cookie '" ~ name ~ "'";
    }

    private static void assertFlag(string name, string flag, bool expected, bool actual)
    {
        if (expected != actual)
            AssertionErrors.fail(cookieLabel(name) ~ " " ~ flag, Boolean.toString(expected), Boolean.toString(actual));
    }

    private static Cookie requireCookie(MvcResult result, string name)
    {
        auto cookie = findCookie(result, name);
        if (cookie is null)
            AssertionErrors.fail("No cookie with name '" ~ name ~ "'");
        return cookie;
    }

    private static Cookie findCookie(MvcResult result, string name)
    {
        foreach (cookie; result.getResponse().getCookies())
            if (cookie.getName() == name)
                return cookie;
        return null;
    }
}

private ModelAndView requireModelAndView(MvcResult result)
{
    auto modelAndView = result.getModelAndView();
    AssertionErrors.assertNotNull("No ModelAndView found", modelAndView is null);
    return modelAndView;
}

/// `HandlerResultMatchers`.
class HandlerResultMatchers
{
    /// Obtain the standard instance through `MockMvcResultMatchers.handler()`.
    protected this() pure nothrow @nogc
    {
    }

    /// Asserts the exact handler type. The Java class token is a template parameter (R4).
    ResultMatcher handlerType(T)()
    {
        return handlerTypeNamed(typeNameOf!T);
    }

    private ResultMatcher handlerTypeNamed(string expected)
    {
        return ResultMatcher.of((MvcResult result) {
            auto handler = result.getHandler();
            AssertionErrors.assertNotNull("No handler", handler is null);
            auto method = cast(HandlerMethod) handler;
            const actual = method is null ? typeid(handler).name : method.getBeanType();
            assertTextEquals("Handler type", nullableText(expected), canonicalTypeName(actual));
        });
    }

    /// Asserts the name of the mapped controller method.
    ResultMatcher methodName(string name)
    {
        return ResultMatcher.of((MvcResult result) {
            auto handler = result.getHandler();
            auto method = cast(HandlerMethod) handler;
            if (method is null)
                AssertionErrors.fail("Not a HandlerMethod: " ~ valueOf(handler));
            assertTextEquals("Handler method", nullableText(name), method.getMethodName());
        });
    }
}

/// `ViewResultMatchers`.
class ViewResultMatchers
{
    /// Obtain the standard instance through `MockMvcResultMatchers.view()`.
    protected this() pure nothrow @nogc
    {
    }

    /// Asserts the selected view name.
    ResultMatcher name(string expectedViewName)
    {
        return ResultMatcher.of((MvcResult result) {
            assertTextEquals("View name", nullableText(expectedViewName), requireModelAndView(result).getViewName());
        });
    }
}

/// `ModelResultMatchers`.
class ModelResultMatchers
{
    /// Obtain the standard instance through `MockMvcResultMatchers.model()`.
    protected this() pure nothrow @nogc
    {
    }

    /// Asserts each named model attribute has a value.
    ResultMatcher attributeExists(string[] names...)
    {
        const expected = names.dup;
        return ResultMatcher.of((MvcResult result) {
            auto model = requireModelAndView(result).getModel();
            foreach (name; expected)
            {
                const message = "Model attribute '" ~ name ~ "' does not exist";
                AssertionErrors.assertNotNull(message, model.get(name).isNull());
            }
        });
    }

    /// Asserts each named model attribute is absent or null.
    ResultMatcher attributeDoesNotExist(string[] names...)
    {
        const expected = names.dup;
        return ResultMatcher.of((MvcResult result) {
            auto model = requireModelAndView(result).getModel();
            foreach (name; expected)
                AssertionErrors.assertNull("Model attribute '" ~ name ~ "' exists", model.get(name).isNull());
        });
    }

    /// Asserts the number of errors on an attribute.
    ResultMatcher attributeErrorCount(string name, int expectedCount)
    {
        return ResultMatcher.of((MvcResult result) {
            const count = getBindingResult(requireModelAndView(result), name).getErrorCount();
            assertCount("Binding/validation error count for attribute '" ~ name ~ "',", expectedCount, count);
        });
    }

    /// Asserts each named attribute has a binding error.
    ResultMatcher attributeHasErrors(string[] names...)
    {
        const expected = names.dup;
        return ResultMatcher.of((MvcResult result) {
            auto modelAndView = requireModelAndView(result);
            foreach (name; expected)
                AssertionErrors.assertTrue("No errors for attribute '" ~ name ~ "'",
                    getBindingResult(modelAndView, name).hasErrors());
        });
    }

    /// Asserts each named attribute has a binding result with zero errors.
    ResultMatcher attributeHasNoErrors(string[] names...)
    {
        const expected = names.dup;
        return ResultMatcher.of((MvcResult result) {
            auto modelAndView = requireModelAndView(result);
            foreach (name; expected)
            {
                auto errors = getBindingResult(modelAndView, name);
                if (errors.hasErrors())
                    AssertionErrors.fail("Unexpected errors for attribute '" ~ name ~ "': " ~ errors.getAllErrors()
                        .toString());
            }
        });
    }

    /// Asserts the binding result has errors on each named field.
    ResultMatcher attributeHasFieldErrors(string name, string[] fieldNames...)
    {
        const expected = fieldNames.dup;
        return ResultMatcher.of((MvcResult result) {
            auto errors = requireAttributeErrors(result, name);
            foreach (fieldName; expected)
                AssertionErrors.assertTrue(fieldErrorMessage(name, fieldName), errors.hasFieldErrors(fieldName));
        });
    }

    /// Asserts the first field error has the expected code.
    ResultMatcher attributeHasFieldErrorCode(string name, string fieldName, string code)
    {
        return ResultMatcher.of((MvcResult result) {
            auto error = requireAttributeErrors(result, name).getFieldError(fieldName);
            AssertionErrors.assertNotNull(fieldErrorMessage(name, fieldName), error is null);
            assertTextEquals("Field error code", nullableText(code), error.getCode());
        });
    }

    /// Asserts the total number of binding and validation errors.
    ResultMatcher errorCount(int expectedCount)
    {
        return ResultMatcher.of((MvcResult result) {
            assertCount("Binding/validation error count", expectedCount, countErrors(requireModelAndView(result)));
        });
    }

    /// Asserts at least one binding or validation error occurred.
    ResultMatcher hasErrors()
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertTrue("Expected binding/validation errors",
                countErrors(requireModelAndView(result)) != 0);
        });
    }

    /// Asserts no binding or validation errors occurred.
    ResultMatcher hasNoErrors()
    {
        return ResultMatcher.of((MvcResult result) {
            requireModelAndView(result).getModel().forEach((string, Any value) {
                auto errors = cast(Errors) value.asObject();
                if (errors !is null && errors.hasErrors())
                    AssertionErrors.fail("Unexpected binding/validation errors: " ~ valueOf(value.asObject()));
            });
        });
    }

    /// Asserts the model size, excluding binding result entries.
    ResultMatcher size(int size)
    {
        return ResultMatcher.of((MvcResult result) {
            enum prefix = BindingResult.MODEL_KEY_PREFIX;
            int count;
            requireModelAndView(result).getModel().forEach((string name, Any) {
                if (name.length < prefix.length || name[0 .. prefix.length] != prefix)
                    ++count;
            });
            assertCount("Model size", size, count);
        });
    }

    private static BindingResult getBindingResult(ModelAndView modelAndView, string name)
    {
        auto value = modelAndView.getModel().get(BindingResult.MODEL_KEY_PREFIX ~ name);
        auto binding = cast(BindingResult) value.asObject();
        AssertionErrors.assertNotNull("No BindingResult for attribute: " ~ name, binding is null);
        return binding;
    }

    private static BindingResult requireAttributeErrors(MvcResult result, string name)
    {
        auto binding = getBindingResult(requireModelAndView(result), name);
        AssertionErrors.assertTrue("No errors for attribute '" ~ name ~ "'", binding.hasErrors());
        return binding;
    }

    private static string fieldErrorMessage(string name, string fieldName)
    {
        return "No errors for field '" ~ fieldName ~ "' of attribute '" ~ name ~ "'";
    }

    private static int countErrors(ModelAndView modelAndView)
    {
        int count;
        modelAndView.getModel().forEach((string, Any value) {
            if (auto errors = cast(Errors) value.asObject())
                count += errors.getErrorCount();
        });
        return count;
    }
}

/// `StatusResultMatchers`.
class StatusResultMatchers
{
    /// Obtain the standard instance through `MockMvcResultMatchers.status()`.
    protected this() pure nothrow @nogc
    {
    }

    /// Asserts the status code is `status`.
    ResultMatcher is_(int status)
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertEquals("Response status", status, result.getResponse().getStatus());
        });
    }

    private ResultMatcher matcher(HttpStatus status)
    {
        const code = status.value();
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertEquals("Status", code, result.getResponse().getStatus());
        });
    }

    private ResultMatcher series(HttpStatus.Series expected)
    {
        return ResultMatcher.of((MvcResult result) {
            const actual = result.getResponse().getStatus();
            auto actualSeries = HttpStatus.Series.resolve(actual);
            if (actualSeries is null)
                throw new IllegalStateException("HTTP status series must not be null");
            if (*actualSeries != expected)
                AssertionErrors.fail("Range for response status value " ~ Integer.toString(actual),
                    expected.name(), actualSeries.name());
        });
    }

    /// Asserts that the response status is in the 1xx range.
    ResultMatcher is1xxInformational()
    {
        return series(HttpStatus.Series.INFORMATIONAL);
    }

    /// Asserts that the response status is in the 2xx range.
    ResultMatcher is2xxSuccessful()
    {
        return series(HttpStatus.Series.SUCCESSFUL);
    }

    /// Asserts that the response status is in the 3xx range.
    ResultMatcher is3xxRedirection()
    {
        return series(HttpStatus.Series.REDIRECTION);
    }

    /// Asserts that the response status is in the 4xx range.
    ResultMatcher is4xxClientError()
    {
        return series(HttpStatus.Series.CLIENT_ERROR);
    }

    /// Asserts that the response status is in the 5xx range.
    ResultMatcher is5xxServerError()
    {
        return series(HttpStatus.Series.SERVER_ERROR);
    }

    /// Asserts the status is 100 (CONTINUE).
    ResultMatcher isContinue()
    {
        return matcher(HttpStatus.CONTINUE);
    }

    /// Asserts the status is 101 (SWITCHING_PROTOCOLS).
    ResultMatcher isSwitchingProtocols()
    {
        return matcher(HttpStatus.SWITCHING_PROTOCOLS);
    }

    /// Asserts the status is 102 (PROCESSING).
    deprecated("since 7.0") ResultMatcher isProcessing()
    {
        return matcher(HttpStatus.PROCESSING);
    }

    /// Asserts the status is 103 (EARLY_HINTS).
    ResultMatcher isEarlyHints()
    {
        return matcher(HttpStatus.EARLY_HINTS);
    }

    /// Asserts the status is 200 (OK).
    ResultMatcher isOk()
    {
        return matcher(HttpStatus.OK);
    }

    /// Asserts the status is 201 (CREATED).
    ResultMatcher isCreated()
    {
        return matcher(HttpStatus.CREATED);
    }

    /// Asserts the status is 202 (ACCEPTED).
    ResultMatcher isAccepted()
    {
        return matcher(HttpStatus.ACCEPTED);
    }

    /// Asserts the status is 203 (NON_AUTHORITATIVE_INFORMATION).
    ResultMatcher isNonAuthoritativeInformation()
    {
        return matcher(HttpStatus.NON_AUTHORITATIVE_INFORMATION);
    }

    /// Asserts the status is 204 (NO_CONTENT).
    ResultMatcher isNoContent()
    {
        return matcher(HttpStatus.NO_CONTENT);
    }

    /// Asserts the status is 205 (RESET_CONTENT).
    ResultMatcher isResetContent()
    {
        return matcher(HttpStatus.RESET_CONTENT);
    }

    /// Asserts the status is 206 (PARTIAL_CONTENT).
    ResultMatcher isPartialContent()
    {
        return matcher(HttpStatus.PARTIAL_CONTENT);
    }

    /// Asserts the status is 207 (MULTI_STATUS).
    ResultMatcher isMultiStatus()
    {
        return matcher(HttpStatus.MULTI_STATUS);
    }

    /// Asserts the status is 208 (ALREADY_REPORTED).
    ResultMatcher isAlreadyReported()
    {
        return matcher(HttpStatus.ALREADY_REPORTED);
    }

    /// Asserts the status is 226 (IM_USED).
    ResultMatcher isImUsed()
    {
        return matcher(HttpStatus.IM_USED);
    }

    /// Asserts the status is 300 (MULTIPLE_CHOICES).
    ResultMatcher isMultipleChoices()
    {
        return matcher(HttpStatus.MULTIPLE_CHOICES);
    }

    /// Asserts the status is 301 (MOVED_PERMANENTLY).
    ResultMatcher isMovedPermanently()
    {
        return matcher(HttpStatus.MOVED_PERMANENTLY);
    }

    /// Asserts the status is 302 (FOUND).
    ResultMatcher isFound()
    {
        return matcher(HttpStatus.FOUND);
    }

    /// Asserts the status is 303 (SEE_OTHER).
    ResultMatcher isSeeOther()
    {
        return matcher(HttpStatus.SEE_OTHER);
    }

    /// Asserts the status is 304 (NOT_MODIFIED).
    ResultMatcher isNotModified()
    {
        return matcher(HttpStatus.NOT_MODIFIED);
    }

    /// Asserts the status is 307 (TEMPORARY_REDIRECT).
    ResultMatcher isTemporaryRedirect()
    {
        return matcher(HttpStatus.TEMPORARY_REDIRECT);
    }

    /// Asserts the status is 308 (PERMANENT_REDIRECT).
    ResultMatcher isPermanentRedirect()
    {
        return matcher(HttpStatus.PERMANENT_REDIRECT);
    }

    /// Asserts the status is 400 (BAD_REQUEST).
    ResultMatcher isBadRequest()
    {
        return matcher(HttpStatus.BAD_REQUEST);
    }

    /// Asserts the status is 401 (UNAUTHORIZED).
    ResultMatcher isUnauthorized()
    {
        return matcher(HttpStatus.UNAUTHORIZED);
    }

    /// Asserts the status is 402 (PAYMENT_REQUIRED).
    ResultMatcher isPaymentRequired()
    {
        return matcher(HttpStatus.PAYMENT_REQUIRED);
    }

    /// Asserts the status is 403 (FORBIDDEN).
    ResultMatcher isForbidden()
    {
        return matcher(HttpStatus.FORBIDDEN);
    }

    /// Asserts the status is 404 (NOT_FOUND).
    ResultMatcher isNotFound()
    {
        return matcher(HttpStatus.NOT_FOUND);
    }

    /// Asserts the status is 405 (METHOD_NOT_ALLOWED).
    ResultMatcher isMethodNotAllowed()
    {
        return matcher(HttpStatus.METHOD_NOT_ALLOWED);
    }

    /// Asserts the status is 406 (NOT_ACCEPTABLE).
    ResultMatcher isNotAcceptable()
    {
        return matcher(HttpStatus.NOT_ACCEPTABLE);
    }

    /// Asserts the status is 407 (PROXY_AUTHENTICATION_REQUIRED).
    ResultMatcher isProxyAuthenticationRequired()
    {
        return matcher(HttpStatus.PROXY_AUTHENTICATION_REQUIRED);
    }

    /// Asserts the status is 408 (REQUEST_TIMEOUT).
    ResultMatcher isRequestTimeout()
    {
        return matcher(HttpStatus.REQUEST_TIMEOUT);
    }

    /// Asserts the status is 409 (CONFLICT).
    ResultMatcher isConflict()
    {
        return matcher(HttpStatus.CONFLICT);
    }

    /// Asserts the status is 410 (GONE).
    ResultMatcher isGone()
    {
        return matcher(HttpStatus.GONE);
    }

    /// Asserts the status is 411 (LENGTH_REQUIRED).
    ResultMatcher isLengthRequired()
    {
        return matcher(HttpStatus.LENGTH_REQUIRED);
    }

    /// Asserts the status is 412 (PRECONDITION_FAILED).
    ResultMatcher isPreconditionFailed()
    {
        return matcher(HttpStatus.PRECONDITION_FAILED);
    }

    /// Asserts the status is 413 (CONTENT_TOO_LARGE).
    ResultMatcher isContentTooLarge()
    {
        return matcher(HttpStatus.CONTENT_TOO_LARGE);
    }

    /// Asserts the status is 413 (PAYLOAD_TOO_LARGE).
    deprecated("since 7.0") ResultMatcher isPayloadTooLarge()
    {
        return matcher(HttpStatus.PAYLOAD_TOO_LARGE);
    }

    /// Asserts the status is 414 (URI_TOO_LONG).
    ResultMatcher isUriTooLong()
    {
        return matcher(HttpStatus.URI_TOO_LONG);
    }

    /// Asserts the status is 415 (UNSUPPORTED_MEDIA_TYPE).
    ResultMatcher isUnsupportedMediaType()
    {
        return matcher(HttpStatus.UNSUPPORTED_MEDIA_TYPE);
    }

    /// Asserts the status is 416 (REQUESTED_RANGE_NOT_SATISFIABLE).
    ResultMatcher isRequestedRangeNotSatisfiable()
    {
        return matcher(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE);
    }

    /// Asserts the status is 417 (EXPECTATION_FAILED).
    ResultMatcher isExpectationFailed()
    {
        return matcher(HttpStatus.EXPECTATION_FAILED);
    }

    /// Asserts the status is 418 (I_AM_A_TEAPOT).
    deprecated("since 7.0") ResultMatcher isIAmATeapot()
    {
        return matcher(HttpStatus.I_AM_A_TEAPOT);
    }

    /// Asserts the status is 421 (MISDIRECTED_REQUEST).
    ResultMatcher isMisdirectedRequest()
    {
        return matcher(HttpStatus.MISDIRECTED_REQUEST);
    }

    /// Asserts the status is 422 (UNPROCESSABLE_CONTENT).
    ResultMatcher isUnprocessableContent()
    {
        return matcher(HttpStatus.UNPROCESSABLE_CONTENT);
    }

    /// Asserts the status is 422 (UNPROCESSABLE_ENTITY).
    deprecated("since 7.0") ResultMatcher isUnprocessableEntity()
    {
        return matcher(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    /// Asserts the status is 423 (LOCKED).
    ResultMatcher isLocked()
    {
        return matcher(HttpStatus.LOCKED);
    }

    /// Asserts the status is 424 (FAILED_DEPENDENCY).
    ResultMatcher isFailedDependency()
    {
        return matcher(HttpStatus.FAILED_DEPENDENCY);
    }

    /// Asserts the status is 425 (TOO_EARLY).
    ResultMatcher isTooEarly()
    {
        return matcher(HttpStatus.TOO_EARLY);
    }

    /// Asserts the status is 426 (UPGRADE_REQUIRED).
    ResultMatcher isUpgradeRequired()
    {
        return matcher(HttpStatus.UPGRADE_REQUIRED);
    }

    /// Asserts the status is 428 (PRECONDITION_REQUIRED).
    ResultMatcher isPreconditionRequired()
    {
        return matcher(HttpStatus.PRECONDITION_REQUIRED);
    }

    /// Asserts the status is 429 (TOO_MANY_REQUESTS).
    ResultMatcher isTooManyRequests()
    {
        return matcher(HttpStatus.TOO_MANY_REQUESTS);
    }

    /// Asserts the status is 431 (REQUEST_HEADER_FIELDS_TOO_LARGE).
    ResultMatcher isRequestHeaderFieldsTooLarge()
    {
        return matcher(HttpStatus.REQUEST_HEADER_FIELDS_TOO_LARGE);
    }

    /// Asserts the status is 451 (UNAVAILABLE_FOR_LEGAL_REASONS).
    ResultMatcher isUnavailableForLegalReasons()
    {
        return matcher(HttpStatus.UNAVAILABLE_FOR_LEGAL_REASONS);
    }

    /// Asserts the status is 500 (INTERNAL_SERVER_ERROR).
    ResultMatcher isInternalServerError()
    {
        return matcher(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    /// Asserts the status is 501 (NOT_IMPLEMENTED).
    ResultMatcher isNotImplemented()
    {
        return matcher(HttpStatus.NOT_IMPLEMENTED);
    }

    /// Asserts the status is 502 (BAD_GATEWAY).
    ResultMatcher isBadGateway()
    {
        return matcher(HttpStatus.BAD_GATEWAY);
    }

    /// Asserts the status is 503 (SERVICE_UNAVAILABLE).
    ResultMatcher isServiceUnavailable()
    {
        return matcher(HttpStatus.SERVICE_UNAVAILABLE);
    }

    /// Asserts the status is 504 (GATEWAY_TIMEOUT).
    ResultMatcher isGatewayTimeout()
    {
        return matcher(HttpStatus.GATEWAY_TIMEOUT);
    }

    /// Asserts the status is 505 (HTTP_VERSION_NOT_SUPPORTED).
    ResultMatcher isHttpVersionNotSupported()
    {
        return matcher(HttpStatus.HTTP_VERSION_NOT_SUPPORTED);
    }

    /// Asserts the status is 506 (VARIANT_ALSO_NEGOTIATES).
    ResultMatcher isVariantAlsoNegotiates()
    {
        return matcher(HttpStatus.VARIANT_ALSO_NEGOTIATES);
    }

    /// Asserts the status is 507 (INSUFFICIENT_STORAGE).
    ResultMatcher isInsufficientStorage()
    {
        return matcher(HttpStatus.INSUFFICIENT_STORAGE);
    }

    /// Asserts the status is 508 (LOOP_DETECTED).
    ResultMatcher isLoopDetected()
    {
        return matcher(HttpStatus.LOOP_DETECTED);
    }

    /// Asserts the status is 509 (BANDWIDTH_LIMIT_EXCEEDED).
    deprecated("since 7.0") ResultMatcher isBandwidthLimitExceeded()
    {
        return matcher(HttpStatus.BANDWIDTH_LIMIT_EXCEEDED);
    }

    /// Asserts the status is 510 (NOT_EXTENDED).
    deprecated("since 7.0") ResultMatcher isNotExtended()
    {
        return matcher(HttpStatus.NOT_EXTENDED);
    }

    /// Asserts the status is 511 (NETWORK_AUTHENTICATION_REQUIRED).
    ResultMatcher isNetworkAuthenticationRequired()
    {
        return matcher(HttpStatus.NETWORK_AUTHENTICATION_REQUIRED);
    }

    /// Asserts the `sendError` message.
    ResultMatcher reason(string reason)
    {
        return ResultMatcher.of((MvcResult result) {
            const actual = result.getResponse().getErrorMessage();
            if (reason != actual || (reason is null) != (actual is null))
                AssertionErrors.fail("Response status reason", reason is null ? "null" : reason,
                    actual is null ? "null" : actual);
        });
    }
}

/// `ContentResultMatchers`.
class ContentResultMatchers
{
    /// Obtain the standard instance through `MockMvcResultMatchers.content()`.
    protected this() pure nothrow @nogc
    {
    }

    /// Asserts the content type equals `contentType` (parameters included).
    ResultMatcher contentType(immutable(char)[] contentType)
    {
        return this.contentType(MediaType.parseMediaType(contentType));
    }

    /// ditto
    ResultMatcher contentType(MediaType contentType)
    {
        return ResultMatcher.of((MvcResult result) {
            const actual = result.getResponse().getContentType();
            AssertionErrors.assertNotNull("Content type not set", actual is null);
            AssertionErrors.assertEquals("Content type", contentType, MediaType.parseMediaType(actual));
        });
    }

    /// Asserts the content type is compatible with `contentType`.
    ResultMatcher contentTypeCompatibleWith(immutable(char)[] contentType)
    {
        return contentTypeCompatibleWith(MediaType.parseMediaType(contentType));
    }

    /// ditto
    ResultMatcher contentTypeCompatibleWith(MediaType contentType)
    {
        return ResultMatcher.of((MvcResult result) {
            const actual = result.getResponse().getContentType();
            AssertionErrors.assertNotNull("Content type not set", actual is null);
            auto actualType = MediaType.parseMediaType(actual);
            AssertionErrors.assertTrue(
                "Content type [" ~ actual ~ "] is not compatible with [" ~ contentType.toString() ~ "]",
                actualType.isCompatibleWith(contentType));
        });
    }

    /// Asserts the character encoding.
    ResultMatcher encoding(Charset characterEncoding)
    {
        return encoding(characterEncoding.name());
    }

    /// ditto
    ResultMatcher encoding(immutable(char)[] characterEncoding)
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertEquals("Character encoding", characterEncoding,
                result.getResponse().getCharacterEncoding());
        });
    }

    /// Asserts the body, decoded with the response encoding, equals `expectedContent`.
    ResultMatcher string(immutable(char)[] expectedContent)
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertEquals("Response content", expectedContent, result.getResponse()
                .getContentAsString());
        });
    }

    /// Asserts the body bytes.
    ResultMatcher bytes(const(ubyte)[] expectedContent)
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertTrue("Response content", result.getResponse()
                .getContentAsByteArray() == expectedContent);
        });
    }

    /// Asserts that the JSON body matches `jsonContent` in lenient mode.
    ResultMatcher json(immutable(char)[] jsonContent)
    {
        return json(jsonContent, JsonCompareMode.LENIENT);
    }

    /// Asserts that the JSON body matches `jsonContent` with the given strictness.
    deprecated("since 6.2, use JsonCompareMode") ResultMatcher json(immutable(char)[] jsonContent, bool strict)
    {
        return json(jsonContent, strict ? JsonCompareMode.STRICT : JsonCompareMode.LENIENT);
    }

    /// Asserts that the JSON body matches `jsonContent` in the selected mode.
    ResultMatcher json(immutable(char)[] jsonContent, JsonCompareMode compareMode)
    {
        return json(jsonContent, JsonComparator.of(compareMode));
    }

    /// Asserts that the JSON body matches `jsonContent` according to the given comparator.
    ResultMatcher json(immutable(char)[] jsonContent, JsonComparator comparator)
    {
        return ResultMatcher.of((MvcResult result) {
            const actual = result.getResponse().getContentAsString("UTF-8");
            comparator.assertIsMatch(NullableJsonText(jsonContent), NullableJsonText(actual));
        });
    }

    /// Accepts a JSON comparator delegate (R9).
    ResultMatcher json(immutable(char)[] jsonContent, JsonComparison delegate(NullableJsonText,
            NullableJsonText) @safe comparator)
    {
        return json(jsonContent, new DelegateJsonComparator(comparator));
    }
}

private final class DelegateJsonComparator : JsonComparator
{
    mixin JsonComparator.Defaults;

    private JsonComparison delegate(NullableJsonText, NullableJsonText) @safe comparator;

    this(JsonComparison delegate(NullableJsonText, NullableJsonText) @safe comparator)
    {
        this.comparator = comparator;
    }

    override JsonComparison compare(NullableJsonText expected, NullableJsonText actual)
    {
        return comparator(expected, actual);
    }
}

/// `HeaderResultMatchers`.
class HeaderResultMatchers
{
    /// Obtain the standard instance through `MockMvcResultMatchers.header()`.
    protected this() pure nothrow @nogc
    {
    }

    /// Asserts the first value of header `name`.
    ResultMatcher string(immutable(char)[] name, immutable(char)[] value)
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertEquals("Response header '" ~ name ~ "'", value,
                result.getResponse().getHeader(name));
        });
    }

    /// Asserts every value of header `name`, in order.
    ResultMatcher stringValues(immutable(char)[] name, immutable(char)[][] values...)
    {
        auto expected = values.dup;
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertTrue("Response header '" ~ name ~ "'", result.getResponse()
                .getHeaders(name) == expected);
        });
    }

    /// Asserts header `name` is present.
    ResultMatcher exists(immutable(char)[] name)
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertTrue("Response should contain header '" ~ name ~ "'",
                result.getResponse().containsHeader(name));
        });
    }

    /// Asserts header `name` is absent.
    ResultMatcher doesNotExist(immutable(char)[] name)
    {
        return ResultMatcher.of((MvcResult result) {
            AssertionErrors.assertTrue("Response should not contain header '" ~ name ~ "'",
                !result.getResponse().containsHeader(name));
        });
    }

    /// Asserts header `name` as a `long`.
    ResultMatcher longValue(immutable(char)[] name, long value)
    {
        return ResultMatcher.of((MvcResult result) {
            auto response = result.getResponse();
            const actual = response.getHeader(name);
            if (actual !is null)
                AssertionErrors.assertEquals("Response header '" ~ name ~ "'", value, Long.parseLong(actual));
            else if (!response.containsHeader(name))
                AssertionErrors.fail("Response does not contain header '" ~ name ~ "'");
        });
    }

    /// Asserts the first value of `name` as an HTTP date, with second precision.
    ResultMatcher dateValue(immutable(char)[] name, long value)
    {
        return ResultMatcher.of((MvcResult result) {
            const actual = result.getResponse().getHeader(name);
            if (actual is null)
                AssertionErrors.fail("Response does not contain header '" ~ name ~ "'");

            auto headers = HttpHeaders.create();
            headers.setDate("expected", value);
            headers.set("actual", actual);
            const expectedDate = headers.getFirstDate("expected");
            const actualDate = headers.getFirstDate("actual");
            if (expectedDate != actualDate)
            {
                const expected = headers.getFirst("expected");
                const message = "Response header '" ~ name ~ "'='" ~ actual
                    ~ "' does not match expected value '" ~ expected ~ "'";
                AssertionErrors.fail(message, Long.toString(expectedDate), Long.toString(actualDate));
            }
        });
    }
}

/// `JsonPathResultMatchers`.
class JsonPathResultMatchers
{
    private JsonPathExpectationsHelper helper;
    private string expectedPrefix;

    /// Compiles the JSON path for subsequent matchers.
    this(string expression)
    {
        helper = JsonPathExpectationsHelper(expression);
    }

    /// Formats the expression with the supplied arguments (R7).
    protected this(Args...)(string expression, Args args) if (Args.length != 0)
    {
        this(String.format(expression, args));
    }

    /// Verifies the prefix before interpreting the rest of the response body as JSON.
    JsonPathResultMatchers prefix(string prefix)
    {
        expectedPrefix = prefix;
        return this;
    }

    private string content(MvcResult result)
    {
        auto body = result.getResponse().getContentAsString("UTF-8");
        if (body.length < expectedPrefix.length)
            AssertionErrors.fail("JSON prefix \"" ~ expectedPrefix ~ "\" not found");
        const actualPrefix = body[0 .. expectedPrefix.length];
        if (actualPrefix != expectedPrefix)
        {
            const message = "Expected a JSON payload prefixed with \"" ~ expectedPrefix;
            AssertionErrors.fail(message ~ "\" but found: '" ~ actualPrefix ~ "'");
        }
        return
        body[expectedPrefix.length .. $];
    }

    /// Asserts the value at the path equals `expectedValue`.
    ResultMatcher value(T)(T expectedValue)
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.assertValue(content(result), expectedValue); });
    }

    /// Asserts a value exists at the path.
    ResultMatcher exists()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.exists(content(result)); });
    }

    /// Asserts no value exists at the path.
    ResultMatcher doesNotExist()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.doesNotExist(content(result)); });
    }

    /// Asserts that this path selects a value, including a JSON null.
    ResultMatcher hasJsonPath()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.hasJsonPath(content(result)); });
    }

    /// Asserts that this path selects no value, including a JSON null.
    ResultMatcher doesNotHaveJsonPath()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.doesNotHaveJsonPath(content(result)); });
    }

    /// Asserts the value at the path is empty.
    ResultMatcher isEmpty()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.assertValueIsEmpty(content(result)); });
    }

    /// Asserts the value at the path is not empty.
    ResultMatcher isNotEmpty()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.assertValueIsNotEmpty(content(result)); });
    }

    /// Asserts the value at the path is a string.
    ResultMatcher isString()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.assertValueIsString(content(result)); });
    }

    /// Asserts the value at the path is a boolean.
    ResultMatcher isBoolean()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.assertValueIsBoolean(content(result)); });
    }

    /// Asserts the value at the path is a number.
    ResultMatcher isNumber()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.assertValueIsNumber(content(result)); });
    }

    /// Asserts the value at the path is an array.
    ResultMatcher isArray()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.assertValueIsArray(content(result)); });
    }

    /// Asserts the value at the path is a map.
    ResultMatcher isMap()
    {
        auto h = helper;
        return ResultMatcher.of((MvcResult result) { h.assertValueIsMap(content(result)); });
    }
}

/// `MockMvcResultHandlers`.
struct MockMvcResultHandlers
{
    /// Prints the request and result to standard output, as Spring's `PrintingResultHandler`.
    static ResultHandler print()
    {
        return new PrintingResultHandler(false);
    }

    /// Prints the result as UTF-8 to the supplied stream.
    static ResultHandler print(OutputStream stream)
    {
        if (stream is null)
            throw new NullPointerException;
        return print(new OutputStreamWriter(stream));
    }

    /// Prints the result to the supplied writer.
    static ResultHandler print(Writer writer)
    {
        return new PrintingResultHandler(writer);
    }

    /// Collects the same text without printing (for assertions on it).
    static PrintingResultHandler log()
    {
        return new PrintingResultHandler(true);
    }
}

/// `PrintingResultHandler`.
final class PrintingResultHandler : ResultHandler
{
    private bool quiet;
    private Writer writer;
    private immutable(char)[] lastText;

    ///
    this(bool quiet) pure nothrow @nogc
    {
        this.quiet = quiet;
    }

    private this(Writer writer)
    {
        if (writer is null)
            throw new NullPointerException;
        this.writer = writer;
    }

    /// The text of the last result handled.
    immutable(char)[] getText() const pure nothrow @nogc
    {
        return lastText;
    }

    /// Throws `IOException` if standard output cannot accept the report.
    void handle(MvcResult result)
    {
        auto request = result.getRequest();
        auto response = result.getResponse();
        immutable(char)[] text;
        void heading(immutable(char)[] title)
        {
            text ~= "\n" ~ title ~ ":\n";
        }

        void line(immutable(char)[] label, immutable(char)[] value)
        {
            immutable(char)[] padded = label;
            while (padded.length < 17)
                padded = " " ~ padded;
            text ~= padded ~ " = " ~ value ~ "\n";
        }

        immutable(char)[] headersText(immutable(char)[][] names,
                immutable(char)[][]delegate(immutable(char)[]) @safe valuesOf)
        {
            immutable(char)[] t = "[";
            foreach (i, name; names)
            {
                t ~= (i == 0 ? "" : ", ") ~ name ~ ":";
                foreach (j, v; valuesOf(name))
                    t ~= (j == 0 ? "" : ", ") ~ "\"" ~ v ~ "\"";
            }
            return t ~ "]";
        }

        heading("MockHttpServletRequest");
        line("HTTP Method", request.getMethod());
        line("Request URI", request.getRequestURI());
        immutable(char)[] params = "{";
        foreach (i, name; request.getParameterNames())
        {
            params ~= (i == 0 ? "" : ", ") ~ name ~ "=[";
            foreach (j, v; request.getParameterValues(name))
                params ~= (j == 0 ? "" : ", ") ~ v;
            params ~= "]";
        }
        line("Parameters", params ~ "}");
        line("Headers", headersText(request.getHeaderNames(), (n) => request.getHeaders(n)));
        line("Body", request.getContentAsByteArray() is null
                ? "null" : cast(immutable(char)[]) request.getContentAsByteArray().idup);
        line("Session Attrs", "{}");
        heading("Handler");
        auto handler = result.getHandler();
        line("Type", handler is null ? "null" : handlerType(handler));
        heading("Resolved Exception");
        auto ex = result.getResolvedException();
        line("Type", ex is null ? "null" : typeid(ex).name);
        heading("MockHttpServletResponse");
        line("Status", decimal(response.getStatus()));
        line("Error message", response.getErrorMessage() is null ? "null" : response.getErrorMessage());
        line("Headers", headersText(response.getHeaderNames(), (n) => response.getHeaders(n)));
        line("Content type", response.getContentType() is null ? "null" : response.getContentType());
        line("Body", response.getContentAsString());
        line("Forwarded URL", "null");
        const redirectedUrl = response.getRedirectedUrl();
        line("Redirected URL", redirectedUrl is null ? "null" : redirectedUrl);
        line("Cookies", "[]");
        lastText = text;
        writeReport(text);
    }

    private void writeReport(string text)
    {
        if (writer is null)
        {
            if (!quiet && !writeStandardOutput(text))
                throw new IOException("Could not write MockMvc result to standard output");
            return;
        }

        try
        {
            writer.write(text);
            writer.flush();
        }
        catch (IOException)
        {
            // Spring's PrintWriter records I/O failures in the writer without throwing from the handler.
        }
    }

    private static immutable(char)[] handlerType(Object handler)
    {
        import flint.web.method : HandlerMethod;

        if (auto method = cast(HandlerMethod) handler)
            return method.getBeanType();
        return typeid(handler).name;
    }
}
