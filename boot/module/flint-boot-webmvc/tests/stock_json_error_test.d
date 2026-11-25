// Flint's own tests for `stockJsonError` (Flint addition): the proof that Boot's JSON error response is stock, which
// the default-JSON-404 specialization requires before it skips the /error dispatch.
module stock_json_error_test;

import flint.boot.autoconfigure.web : ErrorProperties, WebProperties;
import flint.boot.webmvc.autoconfigure.error : BasicErrorController, ErrorPageCustomizer, StockJsonError,
    stockJsonError;
import flint.boot.webmvc.error : DefaultErrorAttributes, ErrorAttributes;
import flint.context.support : GenericApplicationContext;
import flint.engine.aot.any : Any;
import flint.java.util : LinkedHashMap;

@safe:

private alias Include = ErrorProperties.IncludeAttribute;

/// A context with Boot's error beans as ErrorMvcAutoConfiguration creates them, after `configure` adjusts the
/// properties.
private StockJsonError proofFor(scope void delegate(ErrorProperties) @safe configure = null)
{
    auto web = new WebProperties;
    if (configure !is null)
        configure(web.getError());
    auto attributes = new DefaultErrorAttributes;
    auto context = new GenericApplicationContext;
    context.getBeanFactory().registerSingleton("errorAttributes", attributes);
    context.getBeanFactory().registerSingleton("basicErrorController",
            new BasicErrorController(attributes, web.getError()));
    context.getBeanFactory().registerSingleton("errorPageCustomizer", new ErrorPageCustomizer(web));
    context.refresh();
    return stockJsonError(context);
}

@("stock error handling is proved: the error path, path included, and the controller's own response") unittest
{
    import flint.jakarta.servlet : RequestDispatcher;
    import flint.mock.web : MockHttpServletRequest;

    auto proof = proofFor();
    assert(proof !is null);
    assert(proof.getErrorPath() == "/error");
    assert(proof.isIncludePath());
    auto request = new MockHttpServletRequest("GET", "/error");
    request.setAttribute(RequestDispatcher.ERROR_STATUS_CODE, Any.of(404));
    request.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of("/nope"));
    auto response = proof.errorResponse(request);
    assert(response.getStatusCode().value() == 404);
    auto body = cast(LinkedHashMap!(string, Any)) response.getBody().asObject();
    assert(body !is null);
    assert(body.keySet().toArray() == ["timestamp", "status", "error", "path"]);
    assert(body.get("path").get!string == "/nope");
}

@("a custom error path is carried; include-path NEVER is proved without path") unittest
{
    auto proof = proofFor((ErrorProperties error) {
        error.setPath("/oops");
        error.setIncludePath(Include.NEVER);
    });
    assert(proof !is null && proof.getErrorPath() == "/oops" && !proof.isIncludePath());
}

@("an include that depends on the request or the error refuses the proof") unittest
{
    assert(proofFor((ErrorProperties error) { error.setIncludePath(Include.ON_PARAM); }) is null);
    assert(proofFor((ErrorProperties error) { error.setIncludeMessage(Include.ALWAYS); }) is null);
    assert(proofFor((ErrorProperties error) { error.setIncludeMessage(Include.ON_PARAM); }) is null);
    assert(proofFor((ErrorProperties error) { error.setIncludeStacktrace(Include.ALWAYS); }) is null);
    assert(proofFor((ErrorProperties error) { error.setIncludeBindingErrors(Include.ALWAYS); }) is null);
    assert(proofFor((ErrorProperties error) { error.setIncludeException(true); }) is null);
}

private final class CustomErrorController : BasicErrorController
{
    this(ErrorAttributes attributes, ErrorProperties properties)
    {
        super(attributes, properties);
    }
}

private final class CustomErrorAttributes : DefaultErrorAttributes
{
}

@("a subclass of the controller or of the attributes, or a controller over other attributes, refuses the proof")
unittest
{
    static StockJsonError with_(ErrorAttributes bean, ErrorAttributes used, bool subclassController)
    {
        auto web = new WebProperties;
        auto context = new GenericApplicationContext;
        context.getBeanFactory().registerSingleton("errorAttributes", cast(Object) bean);
        context.getBeanFactory().registerSingleton("basicErrorController", subclassController
                ? new CustomErrorController(used, web.getError()) : new BasicErrorController(used, web.getError()));
        context.getBeanFactory().registerSingleton("errorPageCustomizer", new ErrorPageCustomizer(web));
        context.refresh();
        return stockJsonError(context);
    }

    auto stock = new DefaultErrorAttributes;
    assert(with_(stock, stock, false) !is null);
    assert(with_(stock, stock, true) is null);
    auto custom = new CustomErrorAttributes;
    assert(with_(custom, custom, false) is null);
    assert(with_(stock, new DefaultErrorAttributes, false) is null);
}

@("without the error page customizer, or with a second ErrorAttributes bean, there is no proof") unittest
{
    auto web = new WebProperties;
    auto attributes = new DefaultErrorAttributes;
    auto context = new GenericApplicationContext;
    context.getBeanFactory().registerSingleton("errorAttributes", attributes);
    context.getBeanFactory().registerSingleton("basicErrorController",
            new BasicErrorController(attributes, web.getError()));
    context.refresh();
    assert(stockJsonError(context) is null);

    auto second = new GenericApplicationContext;
    second.getBeanFactory().registerSingleton("errorAttributes", attributes);
    second.getBeanFactory().registerSingleton("otherErrorAttributes", new DefaultErrorAttributes);
    second.getBeanFactory().registerSingleton("basicErrorController",
            new BasicErrorController(attributes, web.getError()));
    second.getBeanFactory().registerSingleton("errorPageCustomizer", new ErrorPageCustomizer(web));
    second.refresh();
    assert(stockJsonError(second) is null);
}
