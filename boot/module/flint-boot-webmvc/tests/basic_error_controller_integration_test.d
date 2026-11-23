// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/error/BasicErrorControllerIntegrationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `SpringApplication.run` with `--server.port=0` and a `RestTestClient` become
// webmvc_test_support's `MvcFixture`, the auto-configured DispatcherServlet with the servlet container's error
// dispatch replayed on the same request, so the responses are the JSON the error controller writes; `--spring.web.*`
// arguments are `flint.web.*` entries; `exception.getName()` is the D class name (`typeid(...).name`); `@Valid
// @RequestBody DummyBody` is validated by a spring-context `Validator` that rejects a missing `content`, as
// Hibernate Validator's `@NotNull` would (boot-validation is not in this package's dependencies). The `message` and
// `errors` attributes of a `BindingResult` wait behind FlintErrorAttributesBindingErrors.
module basic_error_controller_integration_test;

import flint.boot.webmvc.autoconfigure.error : BasicErrorController;
import flint.boot.web.error : ErrorAttributeOptions;
import flint.engine.aot.any : Any;
import flint.http : HttpStatus;
import flint.jackson.databind.node : JsonNode;
import flint.jakarta.servlet.http : HttpServletRequest;
import flint.java.lang : IllegalStateException, RuntimeException;
import flint.java.util : HashMap, Map;
import flint.jakarta.validation : Valid;
import flint.validation : Errors, MapBindingResult, Validator;
import flint.web.bind : MethodArgumentNotValidException;
import flint.web.bind.annotation : PostMapping, RequestBody, RequestMapping, ResponseStatus, RestController;
import webmvc_test_support : MvcFixture, controllerRegistry, mvcFixture;

@safe:

private enum ResponseStatus badRequestExpected = () {
    ResponseStatus status;
    status.code = HttpStatus.BAD_REQUEST;
    status.value = HttpStatus.BAD_REQUEST;
    status.reason = "Expected!";
    return status;
}();

private enum ResponseStatus notAcceptable = ResponseStatus(HttpStatus.NOT_ACCEPTABLE, HttpStatus.NOT_ACCEPTABLE);

private enum PostMapping bodyValidationMapping = PostMapping(null, "", ["/bodyValidation"], null,
            null, null, ["application/json"]);

private enum RequestMapping incompatibleTypePath = RequestMapping(null, "", ["/incompatibleType"],
            null, null, null, null, ["text/plain"]);

/// `@ResponseStatus(value = HttpStatus.BAD_REQUEST, reason = "Expected!")`.
@badRequestExpected class ExpectedException : RuntimeException
{
    /// Without a message.
    this() pure nothrow
    {
        super();
    }
}

/// `@ResponseStatus(HttpStatus.NOT_ACCEPTABLE)`.
@notAcceptable class NoReasonExpectedException : RuntimeException
{
    /// With `message`.
    this(string message) pure nothrow
    {
        super(message);
    }
}

/// The posted body.
final class DummyBody
{
    private string content;

    /// The content.
    string getContent() const pure nothrow @nogc
    {
        return content;
    }

    /// Set the content.
    void setContent(string content) pure nothrow @nogc
    {
        this.content = content;
    }
}

/// The test's controller.
@RestController class ErrorsController
{
    /// `foo`.
    string getFoo()
    {
        return "foo";
    }

    /// Fails.
    @RequestMapping("/") string home()
    {
        throw new IllegalStateException("Expected!");
    }

    /// Fails without a message.
    @RequestMapping("/noMessage") string noMessage()
    {
        throw new IllegalStateException();
    }

    /// Fails with `ExpectedException`.
    @RequestMapping("/annotated") string annotated()
    {
        throw new ExpectedException();
    }

    /// Fails with a message and no reason.
    @RequestMapping("/annotatedNoReason") string annotatedNoReason()
    {
        throw new NoReasonExpectedException("Expected message");
    }

    /// Fails with an empty message and no reason.
    @RequestMapping("/annotatedNoMessage") string annotatedNoMessage()
    {
        throw new NoReasonExpectedException("");
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

    /// Echoes a valid body.
    @bodyValidationMapping string bodyValidation(@Valid @RequestBody DummyBody body)
    {
        return
        body.content;
    }

    /// Fails for a `text/plain` handler.
    @incompatibleTypePath string incompatibleType()
    {
        throw new ExpectedException();
    }
}

// `@NotNull private String content`.
private final class NotNullContentValidator : Validator
{
    bool supports(string typeName)
    {
        return typeName.length != 0;
    }

    void validate(Any target, Errors errors)
    {
        if (target.get!DummyBody.getContent() is null)
            errors.rejectValue("content", "NotNull", "must not be null");
    }
}

private alias registry = controllerRegistry!(ErrorsController, "errorsController",
        ExpectedException, NoReasonExpectedException, DummyBody);

private MvcFixture load(string[2][] arguments = null, Object[string] beans = null)
{
    beans["errorsController"] = new ErrorsController;
    return mvcFixture(&registry, arguments, beans, null, [new NotNullContentValidator]);
}

private JsonNode getResponseMap(MvcFixture fixture, string url)
{
    import std.string : indexOf;

    const question = url.indexOf('?');
    const path = question < 0 ? url : url[0 .. question];
    return fixture.performForJson("GET", path.length ? path : "/", question < 0 ? null : url[question + 1 .. $]);
}

private void assertErrorAttributes(JsonNode content, string status, string error, string exception,
        string message, string path)
{
    assert(content !is null);
    assert(content.get("status").asText() == status, "Wrong status");
    assert(content.get("error").asText() == error, "Wrong error");
    if (exception !is null)
        assert(content.has("exception") && content.get("exception").asText() == exception, "Wrong exception");
    else
        assert(!content.has("exception"), "Exception attribute should not be set");
    if (message is null)
        assert(!content.has("message") || content.get("message").isNull(), "Wrong message");
    else
        assert(content.has("message") && content.get("message").asText() == message, "Wrong message");
    assert(content.get("path").asText() == path, "Wrong path");
}

private string[2][] includeAll()
{
    return [
        ["flint.web.error.include-exception", "true"],
        ["flint.web.error.include-stacktrace", "on-param"],
        ["flint.web.error.include-message", "on-param"]
    ];
}

private void exceptionWithStackTraceAndMessage(MvcFixture fixture, string path)
{
    auto response = getResponseMap(fixture, path);
    assertErrorAttributes(response, "500", "Internal Server Error", typeid(IllegalStateException)
            .name, "Expected!", "/");
    assert(response.has("trace"));
}

private void exceptionWithoutStackTraceAndMessage(MvcFixture fixture, string path)
{
    auto response = getResponseMap(fixture, path);
    assertErrorAttributes(response, "500", "Internal Server Error", typeid(IllegalStateException).name, null, "/");
    assert(!response.has("trace"));
}

@("BasicErrorControllerIntegrationTests.testErrorForMachineClientDefault") unittest
{
    auto response = getResponseMap(load(), "?trace=true");
    assertErrorAttributes(response, "500", "Internal Server Error", null, null, "/");
    assert(!response.has("exception") && !response.has("trace"));
}

@("BasicErrorControllerIntegrationTests.testErrorForMachineClientWithParamsTrue") unittest
{
    exceptionWithStackTraceAndMessage(load(includeAll()), "?trace=true&message=true");
}

@("BasicErrorControllerIntegrationTests.testErrorForMachineClientWithParamsFalse") unittest
{
    exceptionWithoutStackTraceAndMessage(load(includeAll()), "?trace=false&message=false");
}

@("BasicErrorControllerIntegrationTests.testErrorForMachineClientWithParamsAbsent") unittest
{
    exceptionWithoutStackTraceAndMessage(load(includeAll()), "");
}

@("BasicErrorControllerIntegrationTests.testErrorForMachineClientNeverParams") unittest
{
    exceptionWithoutStackTraceAndMessage(load([
            ["flint.web.error.include-exception", "true"],
            ["flint.web.error.include-stacktrace", "never"],
            ["flint.web.error.include-message", "never"]
    ]), "?trace=true&message=true");
}

@("BasicErrorControllerIntegrationTests.testErrorForMachineClientAlwaysParams") unittest
{
    exceptionWithStackTraceAndMessage(load([
            ["flint.web.error.include-exception", "true"],
            ["flint.web.error.include-stacktrace", "always"],
            ["flint.web.error.include-message", "always"]
    ]), "?trace=false&message=false");
}

@("BasicErrorControllerIntegrationTests.testErrorForMachineClientAlwaysParamsWithoutMessage") unittest
{
    auto fixture = load([
        ["flint.web.error.include-exception", "true"], ["flint.web.error.include-message", "always"]
    ]);
    auto response = getResponseMap(fixture, "/noMessage");
    assertErrorAttributes(response, "500", "Internal Server Error", typeid(IllegalStateException)
            .name, "No message available", "/noMessage");
}

@("BasicErrorControllerIntegrationTests.testErrorForAnnotatedExceptionWithoutMessage") unittest
{
    auto response = getResponseMap(load([["flint.web.error.include-exception", "true"]]), "/annotated");
    assertErrorAttributes(response, "400", "Bad Request", typeid(ExpectedException).name, null, "/annotated");
}

@("BasicErrorControllerIntegrationTests.testErrorForAnnotatedExceptionWithMessage") unittest
{
    auto response = getResponseMap(load([
            ["flint.web.error.include-exception", "true"],
            ["flint.web.error.include-message", "always"]
    ]), "/annotated");
    assertErrorAttributes(response, "400", "Bad Request", typeid(ExpectedException).name, "Expected!", "/annotated");
}

@("BasicErrorControllerIntegrationTests.testErrorForAnnotatedNoReasonExceptionWithoutMessage") unittest
{
    auto response = getResponseMap(load([["flint.web.error.include-exception", "true"]]), "/annotatedNoReason");
    assertErrorAttributes(response, "406", "Not Acceptable", typeid(NoReasonExpectedException)
            .name, null, "/annotatedNoReason");
}

@("BasicErrorControllerIntegrationTests.testErrorForAnnotatedNoReasonExceptionWithMessage") unittest
{
    auto response = getResponseMap(load([
            ["flint.web.error.include-exception", "true"],
            ["flint.web.error.include-message", "always"]
    ]), "/annotatedNoReason");
    assertErrorAttributes(response, "406", "Not Acceptable", typeid(NoReasonExpectedException)
            .name, "Expected message", "/annotatedNoReason");
}

@("BasicErrorControllerIntegrationTests.testErrorForAnnotatedNoMessageExceptionWithMessage") unittest
{
    auto response = getResponseMap(load([
            ["flint.web.error.include-exception", "true"],
            ["flint.web.error.include-message", "always"]
    ]), "/annotatedNoMessage");
    assertErrorAttributes(response, "406", "Not Acceptable", typeid(NoReasonExpectedException)
            .name, "No message available", "/annotatedNoMessage");
}

private string[2][] withBindingErrors(string include)
{
    return [
        ["flint.web.error.include-exception", "true"],
        ["flint.web.error.include-binding-errors", include]
    ];
}

private string[2][] withMessage(string include)
{
    return [
        ["flint.web.error.include-exception", "true"], ["flint.web.error.include-message", include]
    ];
}

private void bindingExceptionWithoutErrors(MvcFixture fixture, string param)
{
    auto response = getResponseMap(fixture, "/bind" ~ param);
    assertErrorAttributes(response, "400", "Bad Request", typeid(MethodArgumentNotValidException).name, null, "/bind");
    assert(!response.has("errors"));
}

private void bindingExceptionWithoutMessage(MvcFixture fixture, string param)
{
    auto response = getResponseMap(fixture, "/bind" ~ param);
    assertErrorAttributes(response, "400", "Bad Request", typeid(MethodArgumentNotValidException).name, null, "/bind");
    assert(!response.has("errors"));
}

// Boot's DefaultErrorAttributes adds a BindingResult's errors and its "Validation failed for object=..." message.
private void bindingExceptionWithErrors(MvcFixture fixture, string param)
{
    auto response = getResponseMap(fixture, "/bind" ~ param);
    assertErrorAttributes(response, "400", "Bad Request", typeid(MethodArgumentNotValidException).name, null, "/bind");
    assert(response.has("errors"));
}

private void bindingExceptionWithMessage(MvcFixture fixture, string param)
{
    auto response = getResponseMap(fixture, "/bind" ~ param);
    assertErrorAttributes(response, "400", "Bad Request", typeid(MethodArgumentNotValidException)
            .name, "Validation failed for object='test'. Error count: 1", "/bind");
    assert(!response.has("errors"));
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientWithErrorsParamTrue") unittest
{
    bindingExceptionWithErrors(load(withBindingErrors("on-param")), "?errors=true");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientAlwaysErrors") unittest
{
    bindingExceptionWithErrors(load(withBindingErrors("always")), "?errors=false");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientWithMessageParamTrue") unittest
{
    bindingExceptionWithMessage(load(withMessage("on-param")), "?message=true");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientAlwaysMessage") unittest
{
    bindingExceptionWithMessage(load(withMessage("always")), "?message=false");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientWithErrorsParamFalse") unittest
{
    bindingExceptionWithoutErrors(load(withBindingErrors("on-param")), "?errors=false");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientWithErrorsParamAbsent") unittest
{
    bindingExceptionWithoutErrors(load(withBindingErrors("on-param")), "");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientNeverErrors") unittest
{
    bindingExceptionWithoutErrors(load(withBindingErrors("never")), "?errors=true");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientWithMessageParamFalse") unittest
{
    bindingExceptionWithoutMessage(load(withMessage("on-param")), "?message=false");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientWithMessageParamAbsent") unittest
{
    bindingExceptionWithoutMessage(load(withMessage("on-param")), "");
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientNeverMessage") unittest
{
    bindingExceptionWithoutMessage(load(withMessage("never")), "?message=true");
}

@("BasicErrorControllerIntegrationTests.testRequestBodyValidationForMachineClient") unittest
{
    auto response = load([["flint.web.error.include-exception", "true"]]).performForJson("POST",
            "/bodyValidation", null, "application/json", "application/json", "{}");
    assertErrorAttributes(response, "400", "Bad Request", typeid(MethodArgumentNotValidException)
            .name, null, "/bodyValidation");
    assert(!response.has("errors"));
}

@("BasicErrorControllerIntegrationTests.testBindingExceptionForMachineClientDefault") unittest
{
    auto response = load().performForJson("GET", "/bind", "trace=true,message=true", "application/json");
    assert(!response.has("exception"));
    assert(!response.has("trace"));
    assert(!response.has("errors"));
}

@("BasicErrorControllerIntegrationTests.testIncompatibleMediaType") unittest
{
    auto response = load().perform("GET", "/incompatibleType", null, "text/plain");
    assert(response.getStatus() == 400, imported!"std.conv".to!string(response.getStatus()));
    assert(response.getHeader("Content-Type") is null, response.getHeader("Content-Type"));
    assert(response.getContentAsString().length == 0, response.getContentAsString());
}

// `CustomErrorControllerWithoutStatusConfiguration`: the error controller leaves the status out.
private final class WithoutStatusErrorController : BasicErrorController
{
    this(imported!"flint.boot.webmvc.error".ErrorAttributes errorAttributes,
            imported!"flint.boot.autoconfigure.web".ErrorProperties errorProperties)
    {
        super(errorAttributes, errorProperties);
    }

    protected override ErrorAttributeOptions getErrorAttributeOptions(HttpServletRequest request, string mediaType)
    {
        return super.getErrorAttributeOptions(request, mediaType).excluding(ErrorAttributeOptions.Include.STATUS);
    }
}

@("BasicErrorControllerIntegrationTests.customErrorControllerWithoutStatusConfiguration") unittest
{
    import flint.boot.autoconfigure.web : WebProperties;
    import flint.boot.webmvc.error : DefaultErrorAttributes;

    Object[string] beans;
    beans["basicErrorController"] = new WithoutStatusErrorController(new DefaultErrorAttributes,
            new WebProperties().getError());
    auto response = load(null, beans).performForJson("POST", "/bodyValidation", null,
            "application/json", "application/json", "{}");
    assert(!response.has("status"));
}
