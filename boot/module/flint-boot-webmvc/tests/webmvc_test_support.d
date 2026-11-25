/// Flint test fixture for the ported spring-boot v4.2.0 module/spring-boot-webmvc tests: what Flint AOT's generated
/// definitions build for `DispatcherServletAutoConfiguration`, `WebMvcAutoConfiguration` and
/// `ErrorMvcAutoConfiguration` (the beans called directly, in definition order), the controllers' request-mapping
/// rows loaded as the generated registry loads them, and the servlet container's error dispatch (Tomcat's
/// `StandardHostValve`, which `flint.engine.servlet` mirrors) so error responses can be checked without a socket.
module webmvc_test_support;

import flint.boot.autoconfigure.web : ErrorProperties, WebProperties;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.webmvc.autoconfigure : DispatcherServletAutoConfiguration, WebMvcAutoConfiguration;
import flint.boot.webmvc.autoconfigure.error : BasicErrorController, ErrorMvcAutoConfiguration;
import flint.boot.webmvc.error : DefaultErrorAttributes, ErrorAttributes;
import flint.context.support : GenericApplicationContext;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.aot.registry : RegistryPopulator;
import flint.jackson.databind : JsonMapper;
import flint.jackson.databind.node : JsonNode;
import flint.jakarta.servlet : DispatcherType, RequestDispatcher, ServletRequest, ServletResponse;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.web.servlet : DispatcherServlet, HandlerExceptionResolver, View, ViewResolver;

@safe:

// Tomcat's `Response.isError()`: whether `sendError` was called.
private final class ContainerResponse : MockHttpServletResponse
{
    bool error;

    alias sendError = MockHttpServletResponse.sendError;

    override void sendError(int sc, string msg)
    {
        error = true;
        super.sendError(sc, msg);
    }
}

/// `WebProperties` bound from `entries`, as `@EnableConfigurationProperties` binds them.
WebProperties webProperties(string[2][] entries)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    foreach (descriptor; [
        descriptorOf!ErrorProperties(), descriptorOf!(ErrorProperties.Whitelabel)(),
        descriptorOf!(ErrorProperties.IncludeAttribute)(),
        descriptorOf!(WebProperties.LocaleResolver)(), descriptorOf!(WebProperties.Resources)()
    ])
        binder.getDescriptors().add(descriptor);
    return binder.bindOrCreate!WebProperties("flint.web");
}

/// The auto-configured MVC stack of one test: the context, its `DispatcherServlet` and the error beans.
final class MvcFixture
{
    /// The context holding the beans and the generated rows.
    GenericApplicationContext context;
    /// The auto-configured `DispatcherServlet`.
    DispatcherServlet servlet;
    /// The `ErrorAttributes` bean.
    ErrorAttributes errorAttributes;
    /// The `ErrorController` bean.
    BasicErrorController errorController;

    /// Send `method` `uri` (with `query`, its parameters, and `accept`) through the servlet as the container
    /// does: an exception the servlet throws becomes a 500, and an error status (after `sendError` or an
    /// exception) is forwarded to `/error` with the `jakarta.servlet.error.*` attributes, on the same request.
    MockHttpServletResponse perform(string method, string uri, string query = null, string accept = null,
            string contentType = null, string content = null)
    {
        import std.algorithm.iteration : splitter;
        import std.string : indexOf;

        auto request = new MockHttpServletRequest(method, uri);
        if (query.length)
        {
            request.setQueryString(query);
            foreach (pair; query.splitter('&'))
            {
                const equals = pair.indexOf('=');
                if (equals < 0)
                    request.addParameter(pair, "");
                else
                    request.addParameter(pair[0 .. equals], pair[equals + 1 .. $]);
            }
        }
        if (accept.length)
            request.addHeader("Accept", accept);
        if (contentType.length)
            request.setContentType(contentType);
        if (content.length)
            request.setContent(cast(const(ubyte)[]) content);
        auto response = new ContainerResponse;
        Exception failure;
        try
            servlet.service(cast(ServletRequest) request, cast(ServletResponse) response);
        catch (Exception e)
            failure = e;
        if (failure is null && !response.error)
            return response;
        string message = response.getErrorMessage();
        int status = response.getStatus();
        if (failure !is null)
        {
            status = 500;
            message = failure.msg.idup;
            request.setAttribute(RequestDispatcher.ERROR_EXCEPTION, Any.of(cast(Object) failure));
        }
        request.setAttribute(RequestDispatcher.ERROR_STATUS_CODE, Any.of(status));
        request.setAttribute(RequestDispatcher.ERROR_MESSAGE, Any.of(message is null ? "" : message));
        request.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of(request.getRequestURI()));
        request.setRequestURI("/error");
        request.setDispatcherType(DispatcherType.ERROR);
        auto errorResponse = new MockHttpServletResponse;
        errorResponse.setStatus(status);
        servlet.service(cast(ServletRequest) request, cast(ServletResponse) errorResponse);
        return errorResponse;
    }

    /// `perform`, with the JSON body read as a tree.
    JsonNode performForJson(string method, string uri, string query = null, string accept = null,
            string contentType = null, string content = null)
    {
        const 
        body = perform(method, uri, query, accept, contentType, content).getContentAsString();
        assert(body.length, "an empty response body");
        return JsonMapper.builder().build().readTree(body);
    }
}

/// Load `populate` (the rows Flint AOT generates for the test's controllers), register `beans` as the user's
/// singletons, then call the auto-configurations' `@Bean` methods in definition order with `webEntries` bound into
/// `WebProperties`. A user bean named `error` replaces the Whitelabel view, as `@ConditionalOnMissingBean(name =
/// "error")` lets it. `jsonMappers` are the application's `JsonMapper` beans, which the message converters use.
MvcFixture mvcFixture(RegistryPopulator populate, string[2][] webEntries = null, Object[string] beans = null,
        HandlerExceptionResolver[] userResolvers = null,
        imported!"flint.validation".Validator[] validators = null, JsonMapper[] jsonMappers = null)
{
    auto fixture = new MvcFixture;
    auto context = new GenericApplicationContext;
    fixture.context = context;
    context.loadAotRegistry(populate);
    auto factory = context.getBeanFactory();
    foreach (name, bean; beans)
        factory.registerSingleton(name, bean);
    auto properties = webProperties(webEntries);
    factory.registerSingleton("flint.web-org.springframework.boot.autoconfigure.web.WebProperties", properties);
    auto errorConfiguration = new ErrorMvcAutoConfiguration(properties);
    auto attributes = errorConfiguration.errorAttributes();
    fixture.errorAttributes = attributes;
    factory.registerSingleton("errorAttributes", attributes);
    if ("basicErrorController" !in beans)
    {
        fixture.errorController = errorConfiguration.basicErrorController(attributes, null);
        factory.registerSingleton("basicErrorController", fixture.errorController);
    }
    else
        fixture.errorController = cast(BasicErrorController) beans["basicErrorController"];
    ViewResolver[] viewResolvers;
    if (properties.getError().getWhitelabel().isEnabled())
    {
        if ("error" !in beans)
            factory.registerSingleton("error", errorConfiguration.defaultErrorView());
        auto resolver = errorConfiguration.errorViewBeanNameResolver(context);
        factory.registerSingleton("errorViewBeanNameResolver", resolver);
        viewResolvers ~= resolver;
    }
    context.refresh();
    auto support = new WebMvcAutoConfiguration().webMvcConfigurationSupport(context, null,
            [cast(HandlerExceptionResolver) attributes] ~ userResolvers, viewResolvers, jsonMappers, validators, null);
    fixture.servlet = new DispatcherServletAutoConfiguration().dispatcherServlet(support);
    return fixture;
}

/// A populator registering controller `C` under `name`, with its rows, exception handlers and descriptors, and the
/// descriptors of `Types` (the `@ResponseStatus` exceptions, request bodies).
void controllerRegistry(C, string name, Types...)(scope imported!"flint.engine.aot.registry".AotRegistry registry)
{
    import flint.engine.aot.registry : aotContractVersion;
    import flint.web.servlet.mvc.method.aot : exceptionHandlersOf, handlerDescriptorsOf, requestMappingsOf;

    registry.begin(aotContractVersion, 1);
    foreach (row; requestMappingsOf!C(name))
        registry.mapping(row);
    foreach (handler; exceptionHandlersOf!C(name))
        registry.exceptionHandler(handler);
    foreach (descriptor; handlerDescriptorsOf!C())
        registry.descriptor(descriptor);
    static foreach (T; Types)
        registry.descriptor(descriptorOf!T());
    registry.end();
}
