// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/main/java/org/springframework/boot/webmvc/autoconfigure/error/BasicErrorController.java
// with AbstractErrorController.java, ErrorViewResolver.java and ErrorMvcAutoConfiguration.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the error model is `LinkedHashMap!(string, Any)` (R12); the controller's path is
// `/error`, and the dispatcher maps it to `flint.web.error.path` when that is set, since Flint AOT resolves no
// placeholders in mapping paths; `DefaultErrorViewResolver` (templates and static error pages),
// `PreserveErrorControllerTargetClassPostProcessor` and the error-template condition follow with templating; the
// Whitelabel view is resolved by bean name, which `BeanNameViewResolver` does in Boot.

/// `org.springframework.boot.webmvc.autoconfigure.error`: the error controller and its auto-configuration.
module flint.boot.webmvc.autoconfigure.error;

import flint.boot.autoconfigure : AutoConfiguration;
import flint.boot.autoconfigure.condition : ConditionalOnBooleanProperty, ConditionalOnClass,
    ConditionalOnMissingBean, ConditionalOnWebApplication;
import flint.boot.autoconfigure.web : ErrorProperties, WebProperties;
import flint.boot.context.properties : ClassRef, EnableConfigurationProperties;
import flint.boot.web.error : ErrorAttributeOptions;
import flint.boot.web.server : WebServerFactoryCustomizer;
import flint.boot.web.server.servlet : ConfigurableServletWebServerFactory;
import flint.boot.webmvc.error : DefaultErrorAttributes, ErrorAttributes, ErrorController;
import flint.context : ApplicationContext, ApplicationContextAware;
import flint.context.annotation : Bean;
import flint.core.annotation : classOf;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.http : HttpStatus, MediaType, ResponseEntity;
import flint.jakarta.servlet : RequestDispatcher;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.java.util : LinkedHashMap;
import flint.stereotype : Controller;
import flint.web : HttpMediaTypeNotAcceptableException;
import flint.web.bind.annotation : ExceptionHandler, RequestMapping;
import flint.web.context.request : ServletWebRequest;
import flint.web.servlet : ModelAndView, View, ViewResolver;

@safe:

/// Resolves the view of an error, such as a template named after its status.
interface ErrorViewResolver
{
    /// The view of `status`, or `null`.
    ModelAndView resolveErrorView(HttpServletRequest request, HttpStatus status, LinkedHashMap!(string, Any) model);
}

/// The base of error controllers: reads the error attributes and the `trace`, `message`, `errors` and `path`
/// request parameters.
abstract class AbstractErrorController : ErrorController
{
    private ErrorAttributes errorAttributes;
    private ErrorViewResolver[] errorViewResolvers;

    /// Over `errorAttributes` and `errorViewResolvers`.
    this(ErrorAttributes errorAttributes, ErrorViewResolver[] errorViewResolvers = null)
    {
        import flint.java.lang : IllegalArgumentException;

        if (errorAttributes is null)
            throw new IllegalArgumentException("'errorAttributes' must not be null");
        this.errorAttributes = errorAttributes;
        this.errorViewResolvers = errorViewResolvers.dup;
    }

    /// The error attributes of `request`.
    protected LinkedHashMap!(string, Any) getErrorAttributes(HttpServletRequest request, ErrorAttributeOptions options)
    {
        return errorAttributes.getErrorAttributes(new ServletWebRequest(request), options);
    }

    /// Whether the `trace` parameter asks for the stack trace.
    protected bool getTraceParameter(HttpServletRequest request)
    {
        return getBooleanParameter(request, "trace");
    }

    /// Whether the `message` parameter asks for the message.
    protected bool getMessageParameter(HttpServletRequest request)
    {
        return getBooleanParameter(request, "message");
    }

    /// Whether the `errors` parameter asks for binding errors.
    protected bool getErrorsParameter(HttpServletRequest request)
    {
        return getBooleanParameter(request, "errors");
    }

    /// Whether the `path` parameter asks for the path.
    protected bool getPathParameter(HttpServletRequest request)
    {
        return getBooleanParameter(request, "path");
    }

    /// Whether `parameterName` is present and not `false`.
    protected bool getBooleanParameter(HttpServletRequest request, string parameterName)
    {
        import std.uni : sicmp;

        const parameter = request.getParameter(parameterName);
        return parameter !is null && sicmp(parameter, "false") != 0;
    }

    /// The status the servlet engine recorded, else 500.
    protected HttpStatus getStatus(HttpServletRequest request)
    {
        const statusCode = request.getAttribute(RequestDispatcher.ERROR_STATUS_CODE);
        if (statusCode.isNull() || !statusCode.holds!int)
            return HttpStatus.INTERNAL_SERVER_ERROR;
        try
            return HttpStatus.valueOf(statusCode.get!int);
        catch (Exception)
            return HttpStatus.INTERNAL_SERVER_ERROR;
    }

    /// The first view an `ErrorViewResolver` gives, or `null`.
    protected ModelAndView resolveErrorView(HttpServletRequest request, HttpServletResponse,
            HttpStatus status, LinkedHashMap!(string, Any) model)
    {
        foreach (resolver; errorViewResolvers)
        {
            if (auto modelAndView = resolver.resolveErrorView(request, status, model))
                return modelAndView;
        }
        return null;
    }
}

private enum RequestMapping errorPath = RequestMapping("/error");
private enum RequestMapping anyMapping = RequestMapping.init;
private enum RequestMapping htmlMapping = () {
    RequestMapping mapping;
    mapping.produces = [MediaType.TEXT_HTML_VALUE];
    return mapping;
}();

/// Boot's default error controller: an HTML page for browsers, the error attributes as JSON otherwise.
@Controller
@errorPath
class BasicErrorController : AbstractErrorController
{
    private ErrorProperties errorProperties;

    /// Over `errorAttributes`, `errorProperties` and `errorViewResolvers`.
    this(ErrorAttributes errorAttributes, ErrorProperties errorProperties, ErrorViewResolver[] resolvers = null)
    {
        import flint.java.lang : IllegalArgumentException;

        super(errorAttributes, resolvers);
        if (errorProperties is null)
            throw new IllegalArgumentException("'errorProperties' must not be null");
        this.errorProperties = errorProperties;
    }

    /// The HTML error page: a resolved error view, else the `error` view.
    @htmlMapping
    ModelAndView errorHtml(HttpServletRequest request, HttpServletResponse response)
    {
        const status = getStatus(request);
        auto model = getErrorAttributes(request, getErrorAttributeOptions(request, MediaType.TEXT_HTML_VALUE));
        response.setStatus(status.value());
        auto modelAndView = resolveErrorView(request, response, status, model);
        return modelAndView !is null ? modelAndView : new ModelAndView("error", model);
    }

    /// The error attributes, as the response body.
    @anyMapping
    ResponseEntity error(HttpServletRequest request)
    {
        const status = getStatus(request);
        if (status == HttpStatus.NO_CONTENT)
            return ResponseEntity(status);
        auto body = getErrorAttributes(request, getErrorAttributeOptions(request, MediaType.ALL_VALUE));
        return ResponseEntity.of(body, status);
    }

    /// An empty response with the error's status when no representation is acceptable.
    @ExceptionHandler(classOf!HttpMediaTypeNotAcceptableException)
    ResponseEntity mediaTypeNotAcceptable(HttpServletRequest request)
    {
        return ResponseEntity(getStatus(request));
    }

    /// The attributes to include, from the error properties and the request's parameters.
    protected ErrorAttributeOptions getErrorAttributeOptions(HttpServletRequest request, string)
    {
        import core.atomic : atomicLoad, cas;

        alias Include = ErrorAttributeOptions.Include;
        // Flint: the options are one of 32 combinations of these choices, and ErrorAttributeOptions is immutable
        // (`including` and `excluding` return new options), so each combination is built once and shared instead
        // of per request. The choices are read from the properties and the request each time, as Boot reads them.
        uint choice;
        if (errorProperties.isIncludeException())
            choice |= 1;
        if (isIncluded(errorProperties.getIncludeStacktrace(), request, "trace"))
            choice |= 2;
        if (isIncluded(errorProperties.getIncludeMessage(), request, "message"))
            choice |= 4;
        if (isIncluded(errorProperties.getIncludeBindingErrors(), request, "errors"))
            choice |= 8;
        if (isIncluded(errorProperties.getIncludePath(), request, "path"))
            choice |= 16;
        if (auto cached = atomicLoad(optionsByChoice[choice]))
            return cached;
        auto options = ErrorAttributeOptions.defaults();
        if (choice & 1)
            options = options.including(Include.EXCEPTION);
        if (choice & 2)
            options = options.including(Include.STACK_TRACE);
        if (choice & 4)
            options = options.including(Include.MESSAGE);
        if (choice & 8)
            options = options.including(Include.BINDING_ERRORS);
        options = choice & 16 ? options.including(Include.PATH) : options.excluding(Include.PATH);
        cas(&optionsByChoice[choice], cast(ErrorAttributeOptions) null, options);
        return options;
    }

    // The options of each combination of getErrorAttributeOptions' choices, built on first use.
    private ErrorAttributeOptions[32] optionsByChoice;

    /// The error properties.
    protected ErrorProperties getErrorProperties() pure nothrow @nogc
    {
        return errorProperties;
    }

    private bool isIncluded(ErrorProperties.IncludeAttribute include, HttpServletRequest request, string parameter)
    {
        final switch (include)
        {
        case ErrorProperties.IncludeAttribute.ALWAYS:
            return true;
        case ErrorProperties.IncludeAttribute.ON_PARAM:
            return getBooleanParameter(request, parameter);
        case ErrorProperties.IncludeAttribute.NEVER:
            return false;
        }
    }
}

/// Forwards errors to the error controller's path (Boot's `ErrorPageCustomizer`).
final class ErrorPageCustomizer : WebServerFactoryCustomizer
{
    private WebProperties webProperties;

    /// Over `webProperties`.
    this(WebProperties webProperties) pure nothrow @nogc
    {
        this.webProperties = webProperties;
    }

    /// Set the factory's error path to `flint.web.error.path`.
    void customize(ConfigurableServletWebServerFactory factory)
    {
        factory.setErrorPath(webProperties.getError().getPath());
    }
}

/// The Whitelabel error page: Boot's `StaticView`.
final class WhitelabelErrorView : View
{
    /// `text/html;charset=UTF-8`.
    string getContentType()
    {
        return "text/html;charset=UTF-8";
    }

    /// Write the page, unless the response is committed.
    void render(LinkedHashMap!(string, Any) model, HttpServletRequest, HttpServletResponse response)
    {
        if (response.isCommitted())
            return;
        response.setContentType(getContentType());
        string html = "<html><body><h1>Whitelabel Error Page</h1><p>This application has no explicit mapping for "
            ~ "/error, so you are seeing this as a fallback.</p><div id='created'>" ~ htmlEscape(text(model,
                    "timestamp")) ~ "</div><div>There was an unexpected error (type=" ~ htmlEscape(text(model,
                    "error")) ~ ", status=" ~ htmlEscape(text(model, "status")) ~ ").</div>";
        if (model.containsKey("message"))
            html ~= "<div>" ~ htmlEscape(text(model, "message")) ~ "</div>";
        if (model.containsKey("trace"))
            html ~= "<div style='white-space:pre-wrap;'>" ~ htmlEscape(text(model, "trace")) ~ "</div>";
        response.getWriter().write(html ~ "</body></html>");
    }

    // Java's `String.valueOf` of a model value: a `Date` prints as `EEE MMM dd HH:mm:ss zzz yyyy` (in UTC here).
    private static string text(LinkedHashMap!(string, Any) model, string key)
    {
        import std.conv : to;

        auto value = model.get(key);
        if (value.isNull())
            return "null";
        if (value.holds!int)
            return value.get!int
                .to!string;
        if (value.holds!string)
            return value.get!string;
        if (auto o = value.asObject())
        {
            import flint.engine.aot.objects : objectToString;

            return objectToString(o);
        }
        return value.toString();
    }

    private static string htmlEscape(string input) pure
    {
        string escaped;
        foreach (c; input)
        {
            switch (c)
            {
            case '<':
                escaped ~= "&lt;";
                break;
            case '>':
                escaped ~= "&gt;";
                break;
            case '&':
                escaped ~= "&amp;";
                break;
            case '"':
                escaped ~= "&quot;";
                break;
            case '\'':
                escaped ~= "&#39;";
                break;
            default:
                escaped ~= c;
            }
        }
        return escaped;
    }
}

/// Resolves a view name to the `View` bean of that name (Spring MVC's `BeanNameViewResolver`, which Boot adds for the
/// Whitelabel view; flint:webmvc has none yet).
final class ErrorViewBeanNameResolver : ViewResolver
{
    private ApplicationContext context;

    /// Over `context`'s beans.
    this(ApplicationContext context) pure nothrow @nogc
    {
        this.context = context;
    }

    /// The `View` bean named `viewName`, or `null`.
    View resolveViewName(string viewName)
    {
        if (!context.containsBean(viewName))
            return null;
        return cast(View) context.getBean(viewName);
    }
}

/// Auto-configuration of Spring MVC's error handling: `DefaultErrorAttributes`, `BasicErrorController`, the error
/// page forward and the Whitelabel page.
@errorMvcAutoConfiguration
@ConditionalOnWebApplication(ConditionalOnWebApplication.Type.SERVLET)
@ConditionalOnClass(null, ["flint.jakarta.servlet.Servlet", "flint.web.servlet.DispatcherServlet"])
@EnableConfigurationProperties([ClassRef(typeNameOf!WebProperties)])
final class ErrorMvcAutoConfiguration
{
    private WebProperties webProperties;

    /// Over `webProperties`.
    this(WebProperties webProperties) pure nothrow @nogc
    {
        this.webProperties = webProperties;
    }

    /// The error attributes, unless the application defines `ErrorAttributes`.
    @Bean
    @ConditionalOnMissingBean([ClassRef("flint.boot.webmvc.error.ErrorAttributes")])
    DefaultErrorAttributes errorAttributes()
    {
        return new DefaultErrorAttributes;
    }

    /// The error controller, unless the application defines an `ErrorController`.
    @Bean
    @ConditionalOnMissingBean([ClassRef("flint.boot.webmvc.error.ErrorController")])
    BasicErrorController basicErrorController(ErrorAttributes errorAttributes, ErrorViewResolver[] errorViewResolvers)
    {
        return new BasicErrorController(errorAttributes, webProperties.getError(), errorViewResolvers);
    }

    /// Forwards errors to `flint.web.error.path`.
    @Bean
    ErrorPageCustomizer errorPageCustomizer()
    {
        return new ErrorPageCustomizer(webProperties);
    }

    /// The Whitelabel page, as the `error` view, unless `flint.web.error.whitelabel.enabled` is false or the
    /// application defines an `error` bean.
    @errorBean
    @whitelabelEnabled
    @missingErrorBean
    WhitelabelErrorView defaultErrorView()
    {
        return new WhitelabelErrorView;
    }

    /// Resolves the `error` view by bean name.
    @Bean
    @whitelabelEnabled
    @ConditionalOnMissingBean([ClassRef(typeNameOf!ErrorViewBeanNameResolver)])
    ErrorViewBeanNameResolver errorViewBeanNameResolver(ApplicationContext context)
    {
        return new ErrorViewBeanNameResolver(context);
    }
}

// `@AutoConfiguration(before = WebMvcAutoConfiguration.class)`, and
// `@ConditionalOnBooleanProperty(name = "spring.web.error.whitelabel.enabled", matchIfMissing = true)`, as
// constants (dfmt 0.15 cannot parse named UDA arguments).
private enum AutoConfiguration errorMvcAutoConfiguration = () {
    AutoConfiguration configuration;
    configuration.beforeName = ["flint.boot.webmvc.autoconfigure.WebMvcAutoConfiguration"];
    return configuration;
}();

private enum Bean errorBean = () { Bean bean; bean.name = ["error"]; return bean; }();

private enum ConditionalOnMissingBean missingErrorBean = () {
    ConditionalOnMissingBean condition;
    condition.name = ["error"];
    return condition;
}();

private enum ConditionalOnBooleanProperty whitelabelEnabled = () {
    ConditionalOnBooleanProperty condition;
    condition.name = ["flint.web.error.whitelabel.enabled"];
    condition.matchIfMissing = true;
    return condition;
}();

/++
Flint addition: proof that the application answers a JSON error exactly as Boot's stock error handling does, for the
default-JSON-404 specialization (coordination note web-http-404-specialization.md). The specialization writes
the body without the `/error` dispatch only while this holds, and falls back to the generic path otherwise.
+/
final class StockJsonError
{
    private string errorPath;
    private bool includePath;
    private BasicErrorController controller;

    private this(string errorPath, bool includePath, BasicErrorController controller) pure nothrow @nogc
    {
        this.errorPath = errorPath;
        this.includePath = includePath;
        this.controller = controller;
    }

    /// The error controller's path, `flint.web.error.path`, that `ErrorPageCustomizer` registers as the error page.
    string getErrorPath() const pure nothrow @nogc
    {
        return errorPath;
    }

    /// Whether the body has `path` (`flint.web.error.include-path` is `ALWAYS`; it is otherwise `NEVER`).
    bool isIncludePath() const pure nothrow @nogc
    {
        return includePath;
    }

    /// What Boot's `BasicErrorController.error` returns for `request`, an ERROR dispatch's request carrying the
    /// `jakarta.servlet.error.*` attributes: the reference for the specialization's startup self-test.
    ResponseEntity errorResponse(HttpServletRequest request)
    {
        return controller.error(request);
    }

    /++
    Flint's fast path (S6): what `error` returns for the ERROR dispatch of a `sendError(status)` for `requestUri`,
    built without the request: the controller's options, and the stock attributes over the only attributes they
    read that this response keeps (the status and the URI). `stockJsonError` proves the rest is left out: the
    exception and message, which the dispatch also records, are never included.
    +/
    ResponseEntity errorResponse(int status, string requestUri)
    {
        auto attributes = new ErrorPageAttributes(status, requestUri);
        auto body = controller.errorAttributes.getErrorAttributes(attributes, jsonOptions());
        return ResponseEntity.of(body, HttpStatus.valueOf(status));
    }

    // The options `error` passes: no include depends on the request (stockJsonError), so none reads it.
    private ErrorAttributeOptions jsonOptions()
    {
        return controller.getErrorAttributeOptions(null, MediaType.ALL_VALUE);
    }
}

/// The request attributes an error page's `DefaultErrorAttributes` reads for a `sendError` with no exception it can
/// include: the status and the request URI (S6, `StockJsonError.errorResponse`).
private final class ErrorPageAttributes : imported!"flint.web.context.request".WebRequest
{
    private int status;
    private string requestUri;

    this(int status, string requestUri) pure nothrow @nogc
    {
        this.status = status;
        this.requestUri = requestUri;
    }

    Any getAttribute(string name, int scope_)
    {
        if (scope_ != SCOPE_REQUEST)
            return Any.init;
        if (name == RequestDispatcher.ERROR_STATUS_CODE)
            return Any.of(status);
        if (name == RequestDispatcher.ERROR_REQUEST_URI)
            return Any.of(requestUri);
        return Any.init;
    }

    void setAttribute(string, Any, int)
    {
    }

    void removeAttribute(string, int)
    {
    }

    string[] getAttributeNames(int scope_)
    {
        return scope_ == SCOPE_REQUEST ? [
            RequestDispatcher.ERROR_STATUS_CODE, RequestDispatcher.ERROR_REQUEST_URI
        ] : null;
    }

    string getHeader(string)
    {
        return null;
    }

    string[] getHeaderValues(string)
    {
        return null;
    }

    string getParameter(string)
    {
        return null;
    }

    string[] getParameterValues(string)
    {
        return null;
    }

    string getContextPath()
    {
        return null;
    }

    string getDescription(bool)
    {
        return "uri=" ~ requestUri;
    }
}

/++
Flint addition: the `StockJsonError` proof for `context`, or `null` when Boot's JSON error response is not stock
there. It holds when:
$(UL
    $(LI the only `ErrorController` bean is exactly `BasicErrorController` and the only `ErrorAttributes` bean exactly
        `DefaultErrorAttributes`, not subclasses, whose overrides could change the body, and the controller uses that
        bean;)
    $(LI `ErrorPageCustomizer` registers the controller's path as the error page;)
    $(LI no include depends on the request or the error: `include-exception` is false, `include-stacktrace`,
        `include-message` and `include-binding-errors` are `NEVER`, and `include-path` is `NEVER` or `ALWAYS`.)
)
The JSON mapper (`flint.boot.jackson.autoconfigure.stockJsonMapper`) and the dispatcher's side are proved by their
owners. None of it replaces the startup comparison of the specialization's bytes with the generic path's.
+/
StockJsonError stockJsonError(ApplicationContext context)
{
    alias Include = ErrorProperties.IncludeAttribute;

    const controllers = context.getBeanNamesForType!ErrorController();
    const attributes = context.getBeanNamesForType!ErrorAttributes();
    if (controllers.length != 1 || attributes.length != 1
            || context.getBeanNamesForType!ErrorPageCustomizer().length != 1)
        return null;
    auto controller = cast(BasicErrorController) context.getBean(controllers[0]);
    auto errorAttributes = context.getBean(attributes[0]);
    if (controller is null || typeid(controller) !is typeid(BasicErrorController)
            || typeid(errorAttributes) !is typeid(DefaultErrorAttributes)
            || cast(Object) controller.errorAttributes !is errorAttributes)
        return null;
    auto properties = controller.getErrorProperties();
    if (properties.isIncludeException() || properties.getIncludeStacktrace() != Include.NEVER
            || properties.getIncludeMessage() != Include.NEVER || properties.getIncludeBindingErrors() != Include.NEVER)
        return null;
    const includePath = properties.getIncludePath();
    if (includePath == Include.ON_PARAM)
        return null;
    return new StockJsonError(properties.getPath(), includePath == Include.ALWAYS, controller);
}

/++
Flint addition: the error-page shortcut for Boot's stock JSON error (docs/spring/phase1/fast-path.md, "The
error-page shortcut"). The servlet engine asks it at each error-page forward, after the `jakarta.servlet.error.*`
attributes are set and before the ERROR dispatch; it writes what that dispatch would write, or answers `false` having
written nothing, and the engine forwards generically.

`install` holds only when the whole ERROR dispatch is proved stock at startup:
$(UL
    $(LI Boot: `stockJsonError`, and the Jackson converter's mapper is exactly the auto-configured one, the
        `stockMapper` proof (`flint.boot.jackson.autoconfigure.stockJsonMapper`, which Flint AOT's customizer passes,
        since this package does not depend on boot-jackson);)
    $(LI the engine: the ERROR dispatch to the error path runs no filter, and ends at the `DispatcherServlet`;)
    $(LI the dispatcher: `ErrorShortcutRoute.prove`, for `BasicErrorController.error` and its body type.)
)
Per request it writes a 404 for the error path, for `GET`, `POST`, `PUT`, `DELETE` or `PATCH` (HEAD and the methods
`HttpServlet` answers itself stay generic), at most one `Accept` field the route answers, and a response without a
`Content-Type` of its own. The body is the controller's own `ResponseEntity` (its timestamp, status, reason and path,
from the same attributes), written by the converter's mapper; headers the request's handler set stay on the
response, as they do through the forward.
+/
final class StockErrorPageShortcut : Shortcut, imported!"flint.engine.aot.fast".FastErrorPage
{
    import flint.boot.web.server.engine : FlintServletWebServerFactory;
    import flint.engine.aot.fast : FastExchange;
    import flint.jackson.databind : JsonMapper;
    import flint.web.servlet : DispatcherServlet;
    import flint.web.servlet.mvc.method.fast : ErrorShortcutRoute;

    /// Boot's proof that the application's `JsonMapper` is the auto-configured one, or `null`.
    alias JsonMapperProof = JsonMapper function(ApplicationContext context) @safe;

    private ApplicationContext context;
    private JsonMapperProof stockMapper;
    private StockJsonError stock;
    private ErrorShortcutRoute route;
    // S6: the dispatch of an unmatched GET ends in sendError(404) with nothing else on the response.
    private bool unmatchedProved;
    private string unmatchedWhy;

    /// Over `context`, with Boot's Jackson proof.
    this(ApplicationContext context, JsonMapperProof stockMapper) pure nothrow @nogc
    {
        this.context = context;
        this.stockMapper = stockMapper;
    }

    /// Whether this engine's error forwards may be written in place: its ERROR dispatch to the error path runs no
    /// filter and ends at a `DispatcherServlet` that `prove` accepts.
    bool install(Engine engine)
    {
        import flint.jakarta.servlet : DispatcherType;

        auto error = stockJsonError(context);
        if (error is null || engine.filtersFor(DispatcherType.ERROR, error.getErrorPath()).length != 0)
            return false;
        auto servlet = cast(DispatcherServlet) engine.defaultServletInstance();
        return servlet !is null && prove(servlet);
    }

    /// The Boot and dispatcher proofs against `servlet`; `install` adds the engine's.
    bool prove(DispatcherServlet servlet)
    {
        import flint.web.method : HandlerMethod;

        route = null;
        stock = stockJsonError(context);
        auto mapper = stockMapper is null ? null : stockMapper(context);
        if (stock is null || mapper is null)
            return false;
        auto controller = cast(Object) stock.controller;
        auto proved = ErrorShortcutRoute.prove(servlet, stock.getErrorPath(), bodyType(),
                (HandlerMethod handler) => handler.getBean() is controller && handler.getMethodName() == "error");
        if (proved is null || proved.converterMapper() !is cast(Object) mapper)
            return false;
        route = proved;
        // S6: the resolver ahead of Spring's is the stock error attributes, which only record the exception.
        auto errorAttributes = cast(Object) stock.controller.errorAttributes;
        unmatchedProved = ErrorShortcutRoute.provesUnmatched(servlet, (Object resolver) => resolver is errorAttributes
                && typeid(resolver) is typeid(DefaultErrorAttributes), unmatchedWhy);
        return true;
    }

    /// S6: why the unmatched-GET proof failed, or null when it holds (diagnosis, tests).
    string unmatchedFailure() const pure nothrow @nogc
    {
        return unmatchedProved ? null : unmatchedWhy is null ? "not proved" : unmatchedWhy;
    }

    /++
    S6: write the 404 of a `GET` that no registration of the dispatcher's first mapping matches, with no servlet
    objects: `provesUnmatched` says the dispatch ends in `sendError(404)` with nothing else on the response; the
    engine's forward to this page then runs no filter (`install`), and the page writes the controller's own body
    for the status and URI (`StockJsonError.errorResponse`) after the mapped filters' fields, as `writeErrorPage`
    writes it on the forwarded response. `false`, having written nothing, for anything else.
    +/
    bool writeUnmatched(ref scope FastExchange exchange, string page, scope const(char)[] requestUri)
    {
        if (route is null || !unmatchedProved || page != stock.getErrorPath() || exchange.method != "GET")
            return false;
        size_t slot;
        if (!route.admits(exchange, slot))
            return false;
        return route.write(exchange, slot, stock.errorResponse(404, requestUri.idup));
    }

    /// Write the error page of `status` at `page` as the ERROR dispatch would, or answer `false` having written
    /// nothing.
    bool writeErrorPage(HttpServletRequest request, HttpServletResponse response, int status, string page)
    {
        if (route is null || status != 404 || page != stock.getErrorPath()
                || !shortcutMethod(request.getMethod()) || response.isCommitted() || response.getContentType() !is null)
            return false;
        size_t slot;
        if (!route.admits(request, slot))
            return false;
        return route.write(response, slot, stock.errorResponse(request));
    }

    // The body type `BasicErrorController.error` returns: the error attributes' map.
    private static string bodyType()
    {
        return Any.of(new LinkedHashMap!(string, Any)).typeName();
    }

    // The methods `FrameworkServlet` sends straight to `processRequest`; HEAD drops the body, and OPTIONS and TRACE
    // have `HttpServlet` answers of their own.
    private static bool shortcutMethod(string method) pure nothrow @nogc
    {
        switch (method)
        {
        case "GET", "POST", "PUT", "DELETE", "PATCH":
            return true;
        default:
            return false;
        }
    }
}

/++
Flint addition: the `WebServerFactoryCustomizer` Flint AOT generates with the fast path
(`flintAotErrorPageShortcut`, when the fast path is on and the application has Boot's web server, error handling and
Jackson): it gives the server factory a `StockErrorPageShortcut` over the application context, with Boot's Jackson
proof. Nothing else creates one, so an application without it links none of the shortcut.
+/
final class ErrorPageShortcutCustomizer : WebServerFactoryCustomizer, ApplicationContextAware
{
    private StockErrorPageShortcut.JsonMapperProof stockMapper;
    private ApplicationContext context;

    /// With Boot's Jackson proof, `flint.boot.jackson.autoconfigure.stockJsonMapper`.
    this(StockErrorPageShortcut.JsonMapperProof stockMapper) pure nothrow @nogc
    {
        this.stockMapper = stockMapper;
    }

    void setApplicationContext(ApplicationContext context)
    {
        this.context = context;
    }

    void customize(ConfigurableServletWebServerFactory factory)
    {
        import flint.boot.web.server.engine : FlintServletWebServerFactory;

        if (auto server = cast(FlintServletWebServerFactory) factory)
            if (context !is null)
                server.setErrorPageShortcut(new StockErrorPageShortcut(context, stockMapper));
    }
}

// The engine's `ErrorPageShortcut` and `ServletEngine`, named through the server factory (this package reaches the
// engine only through boot-web-server).
private alias Shortcut = imported!"flint.boot.web.server.engine".FlintServletWebServerFactory.ErrorPageShortcut;
private alias Engine = imported!"std.traits".Parameters!(Shortcut.install)[0];
