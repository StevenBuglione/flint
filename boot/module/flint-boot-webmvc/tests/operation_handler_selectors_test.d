// Flint's own tests for `OperationHandler` (Flint addition): the selectors an `ALL_REMAINING` (`{*path}`) mapping
// reads from the request path, as Spring MVC's path variable for `/**` gives them to the operation.
module operation_handler_selectors_test;

import flint.boot.actuate.endpoint.web : WebEndpointResponse, WebOperation, WebOperationRequestPredicate;
import flint.boot.webmvc.actuate.endpoint.web : OperationHandler;
import flint.engine.aot.any : Any;
import flint.mock.web : MockHttpServletRequest;

@safe:

/// The operation's selectors, recorded.
private final class Recording : WebOperation
{
    string[] selectors;
    bool invoked;

    string getId()
    {
        return "health";
    }

    WebOperationRequestPredicate getRequestPredicate()
    {
        return null;
    }

    WebEndpointResponse invoke(string[] selectors)
    {
        this.selectors = selectors;
        invoked = true;
        return new WebEndpointResponse(Any.init, WebEndpointResponse.STATUS_NO_CONTENT);
    }
}

private string[] selectorsFor(string mapping, string uri, string contextPath = "")
{
    auto operation = new Recording;
    auto request = new MockHttpServletRequest("GET", uri);
    request.setContextPath(contextPath);
    new OperationHandler(operation, mapping).handle(request);
    assert(operation.invoked);
    return operation.selectors;
}

@("an ALL_REMAINING selector is the non-empty segments after the mapping's prefix") unittest
{
    assert(selectorsFor("/actuator/health/{*path}", "/actuator/health/db") == ["db"]);
    assert(selectorsFor("/actuator/health/{*path}", "/actuator/health/a/b//c/") == ["a", "b", "c"]);
    assert(selectorsFor("/actuator/health/{*path}", "/app/actuator/health/db/x", "/app") == [
        "db", "x"
    ]);
}

@("no selector without a capture, or with nothing after the prefix") unittest
{
    assert(selectorsFor("/actuator/health", "/actuator/health/db") is null);
    assert(selectorsFor("/actuator/health/{*path}", "/actuator/health/") is null);
    assert(selectorsFor("/actuator/health/{*path}", "/actuator/health//") is null);
}
