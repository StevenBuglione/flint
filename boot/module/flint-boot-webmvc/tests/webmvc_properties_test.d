/// Flint tests: `flint.mvc.*` carries Boot's defaults and binds with Boot's keys.
module webmvc_properties_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.webmvc.autoconfigure : WebMvcProperties;
import flint.engine.aot.descriptor : descriptorOf;

@safe:

unittest
{
    auto properties = new WebMvcProperties;
    assert(properties.isDispatchOptionsRequest() && !properties.isDispatchTraceRequest());
    assert(properties.isPublishRequestHandledEvents());
    assert(properties.getStaticPathPattern() == "/**" && properties.getWebjarsPathPattern() == "/webjars/**");
    assert(properties.getServlet().getPath() == "/" && properties.getServlet().getLoadOnStartup() == -1);
    assert(properties.getPathmatch().getMatchingStrategy() == WebMvcProperties.MatchingStrategy.PATH_PATTERN_PARSER);
    assert(!properties.getProblemdetails().isEnabled());
}

unittest
{
    auto source = new MapConfigurationPropertySource("test", [
        ["spring.mvc.servlet.path", "/app"], ["flint.mvc.problemdetails.enabled", "true"],
        ["flint.mvc.log-resolved-exception", "true"]
    ]);
    auto binder = new Binder([cast(ConfigurationPropertySource) source]);
    foreach (descriptor; [
        descriptorOf!(WebMvcProperties.Servlet)(), descriptorOf!(WebMvcProperties.Problemdetails)()
    ])
        binder.getDescriptors().add(descriptor);
    auto properties = binder.bind!WebMvcProperties("flint.mvc").get();
    assert(properties.getServlet().getPath() == "/app");
    assert(properties.getProblemdetails().isEnabled());
    assert(properties.isLogResolvedException());
}
