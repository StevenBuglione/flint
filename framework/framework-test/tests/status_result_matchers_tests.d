/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/result/StatusResultMatchersTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: explicit method references replace Java reflection.
+/
module status_result_matchers_tests;

import flint.http : HttpStatus;
import flint.java.lang : AssertionError, IllegalStateException;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.test.web.servlet : DefaultMvcResult, ResultMatcher;
import flint.test.web.servlet.result : MockMvcResultMatchers;

@safe:

@("httpStatusCodeResultMatchers")
unittest
{
    auto matchers = MockMvcResultMatchers.status();
    ResultMatcher delegate() @safe[] factories = [
        &matchers.isContinue, &matchers.isSwitchingProtocols, &matchers.isProcessing,
        &matchers.isEarlyHints, &matchers.isOk, &matchers.isCreated, &matchers.isAccepted,
        &matchers.isNonAuthoritativeInformation, &matchers.isNoContent, &matchers.isResetContent,
        &matchers.isPartialContent, &matchers.isMultiStatus, &matchers.isAlreadyReported,
        &matchers.isImUsed, &matchers.isMultipleChoices, &matchers.isMovedPermanently,
        &matchers.isFound, &matchers.isSeeOther, &matchers.isNotModified,
        &matchers.isTemporaryRedirect, &matchers.isPermanentRedirect, &matchers.isBadRequest,
        &matchers.isUnauthorized, &matchers.isPaymentRequired, &matchers.isForbidden,
        &matchers.isNotFound, &matchers.isMethodNotAllowed, &matchers.isNotAcceptable,
        &matchers.isProxyAuthenticationRequired, &matchers.isRequestTimeout, &matchers.isConflict,
        &matchers.isGone, &matchers.isLengthRequired, &matchers.isPreconditionFailed,
        &matchers.isContentTooLarge, &matchers.isPayloadTooLarge, &matchers.isUriTooLong,
        &matchers.isUnsupportedMediaType, &matchers.isRequestedRangeNotSatisfiable,
        &matchers.isExpectationFailed, &matchers.isIAmATeapot, &matchers.isMisdirectedRequest,
        &matchers.isUnprocessableContent, &matchers.isUnprocessableEntity, &matchers.isLocked,
        &matchers.isFailedDependency, &matchers.isTooEarly, &matchers.isUpgradeRequired,
        &matchers.isPreconditionRequired, &matchers.isTooManyRequests,
        &matchers.isRequestHeaderFieldsTooLarge, &matchers.isUnavailableForLegalReasons,
        &matchers.isInternalServerError, &matchers.isNotImplemented, &matchers.isBadGateway,
        &matchers.isServiceUnavailable, &matchers.isGatewayTimeout,
        &matchers.isHttpVersionNotSupported, &matchers.isVariantAlsoNegotiates,
        &matchers.isInsufficientStorage, &matchers.isLoopDetected, &matchers.isBandwidthLimitExceeded,
        &matchers.isNotExtended, &matchers.isNetworkAuthenticationRequired,
    ];

    auto statuses = HttpStatus.values();
    assert(factories.length == statuses.length);
    auto request = new MockHttpServletRequest;
    foreach (index, status; statuses)
    {
        auto response = new MockHttpServletResponse;
        response.setStatus(status.value());
        factories[index]().match(new DefaultMvcResult(request, response));
    }
}

@("statusRanges")
unittest
{
    auto matchers = MockMvcResultMatchers.status();
    ResultMatcher[5] ranges = [
        matchers.is1xxInformational(), matchers.is2xxSuccessful(), matchers.is3xxRedirection(),
        matchers.is4xxClientError(), matchers.is5xxServerError(),
    ];
    auto request = new MockHttpServletRequest;
    foreach (status; HttpStatus.values())
    {
        auto response = new MockHttpServletResponse;
        response.setStatus(status.value());
        ranges[status.series().value() - 1].match(new DefaultMvcResult(request, response));
    }
}

@("MockMvc status ranges accept unregistered codes and reject invalid series")
unittest
{
    auto response = new MockHttpServletResponse;
    auto result = new DefaultMvcResult(new MockHttpServletRequest, response);
    auto status = MockMvcResultMatchers.status();
    response.setStatus(299);
    status.is_(299).match(result);
    status.is2xxSuccessful().match(result);
    try
    {
        status.is4xxClientError().match(result);
        assert(false);
    }
    catch (AssertionError failure)
    {
        enum expected = "Range for response status value 299 expected:<CLIENT_ERROR> but was:<SUCCESSFUL>";
        assert(failure.getMessage() == expected);
    }

    response.setStatus(600);
    try
    {
        status.is5xxServerError().match(result);
        assert(false);
    }
    catch (IllegalStateException failure)
    {
        assert(failure.getMessage() == "HTTP status series must not be null");
    }
}

@("MockMvc status reasons distinguish an empty message from an absent message")
unittest
{
    auto response = new MockHttpServletResponse;
    auto result = new DefaultMvcResult(new MockHttpServletRequest, response);
    auto status = MockMvcResultMatchers.status();
    try
    {
        status.reason("").match(result);
        assert(false);
    }
    catch (AssertionError failure)
    {
        assert(failure.getMessage() == "Response status reason expected:<> but was:<null>");
    }

    response.sendError(400, "");
    status.reason("").match(result);
}
