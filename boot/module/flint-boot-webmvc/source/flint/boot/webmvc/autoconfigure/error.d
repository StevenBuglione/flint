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
import flint.context : ApplicationContext;
import flint.context.annotation : Bean;
import flint.core.annotation : classOf;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.http : HttpStatus, MediaType, ResponseEntity;
import flint.jakarta.servlet : RequestDispatcher;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.java.time : Instant;
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
@Controller @errorPath class BasicErrorController : AbstractErrorController
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
    @htmlMapping ModelAndView errorHtml(HttpServletRequest request, HttpServletResponse response)
    {
        const status = getStatus(request);
        auto model = getErrorAttributes(request, getErrorAttributeOptions(request, MediaType.TEXT_HTML_VALUE));
        response.setStatus(status.value());
        auto modelAndView = resolveErrorView(request, response, status, model);
        return modelAndView !is null ? modelAndView : new ModelAndView("error", model);
    }

    /// The error attributes, as the response body.
    @anyMapping ResponseEntity error(HttpServletRequest request)
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
        alias Include = ErrorAttributeOptions.Include;
        auto options = ErrorAttributeOptions.defaults();
        if (errorProperties.isIncludeException())
            options = options.including(Include.EXCEPTION);
        if (isIncluded(errorProperties.getIncludeStacktrace(), request, "trace"))
            options = options.including(Include.STACK_TRACE);
        if (isIncluded(errorProperties.getIncludeMessage(), request, "message"))
            options = options.including(Include.MESSAGE);
        if (isIncluded(errorProperties.getIncludeBindingErrors(), request, "errors"))
            options = options.including(Include.BINDING_ERRORS);
        return isIncluded(errorProperties.getIncludePath(), request, "path") ? options.including(
                Include.PATH) : options.excluding(Include.PATH);
    }

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

    // Java's `Object.toString()` of a model value: `Date` prints as `EEE MMM dd HH:mm:ss zzz yyyy`, in UTC here.
    private static string text(LinkedHashMap!(string, Any) model, string key)
    {
        import std.conv : to;

        auto value = model.get(key);
        if (value.isNull())
            return "null";
        if (value.holds!Instant)
            return dateText(value.get!Instant);
        if (value.holds!int)
            return value.get!int
                .to!string;
        if (value.holds!string)
            return value.get!string;
        return value.toString();
    }

    private static string dateText(Instant instant)
    {
        import std.datetime.systime : SysTime, unixTimeToStdTime;
        import std.datetime.timezone : UTC;
        import std.format : format;

        static immutable days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        static immutable months = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
        ];
        const time = SysTime(unixTimeToStdTime(instant.getEpochSecond()), UTC());
        return format("%s %s %02d %02d:%02d:%02d UTC %04d", days[time.dayOfWeek],
                months[time.month - 1], time.day, time.hour, time.minute, time.second, time.year);
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
@errorMvcAutoConfiguration @ConditionalOnWebApplication(ConditionalOnWebApplication.Type.SERVLET)
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
    @Bean @ConditionalOnMissingBean([ClassRef("flint.boot.webmvc.error.ErrorAttributes")])
    DefaultErrorAttributes errorAttributes()
    {
        return new DefaultErrorAttributes;
    }

    /// The error controller, unless the application defines an `ErrorController`.
    @Bean @ConditionalOnMissingBean([ClassRef("flint.boot.webmvc.error.ErrorController")])
    BasicErrorController basicErrorController(ErrorAttributes errorAttributes, ErrorViewResolver[] errorViewResolvers)
    {
        return new BasicErrorController(errorAttributes, webProperties.getError(), errorViewResolvers);
    }

    /// Forwards errors to `flint.web.error.path`.
    @Bean ErrorPageCustomizer errorPageCustomizer()
    {
        return new ErrorPageCustomizer(webProperties);
    }

    /// The Whitelabel page, as the `error` view, unless `flint.web.error.whitelabel.enabled` is false or the
    /// application defines an `error` bean.
    @errorBean @whitelabelEnabled @missingErrorBean WhitelabelErrorView defaultErrorView()
    {
        return new WhitelabelErrorView;
    }

    /// Resolves the `error` view by bean name.
    @Bean @whitelabelEnabled @ConditionalOnMissingBean([
        ClassRef(typeNameOf!ErrorViewBeanNameResolver)
    ])
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
