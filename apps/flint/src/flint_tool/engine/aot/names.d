/// The annotation names Flint AOT acts on (docs/spring/aot-contract.md section 2.2) and Spring's naming rules.
module flint_tool.engine.aot.names;

@safe:

/// `@FlintBootApplication`.
enum flintBootApplication = "flint.boot.autoconfigure.FlintBootApplication";
/// ADR-029's `@FlintApplication`, Boot's class used as a bare UDA: an alias of `@FlintBootApplication`.
enum flintApplication = "flint.boot.FlintApplication";
/// `@EnableAutoConfiguration`.
enum enableAutoConfiguration = "flint.boot.autoconfigure.EnableAutoConfiguration";
/// Boot's `spring.boot.enableautoconfiguration`, under Flint's prefix.
enum enableAutoConfigurationProperty = "flint.boot.enableautoconfiguration";
/// `@AutoConfiguration`.
enum autoConfiguration = "flint.boot.autoconfigure.AutoConfiguration";
/// `@AutoConfigureOrder`.
enum autoConfigureOrder = "flint.boot.autoconfigure.AutoConfigureOrder";
/// `@AutoConfigureAfter`.
enum autoConfigureAfter = "flint.boot.autoconfigure.AutoConfigureAfter";
/// `@AutoConfigureBefore`.
enum autoConfigureBefore = "flint.boot.autoconfigure.AutoConfigureBefore";

/// `@Component`.
enum component = "flint.stereotype.Component";
/// `@Controller`.
enum controller = "flint.stereotype.Controller";
/// `@Configuration`.
enum configuration = "flint.context.annotation.Configuration";
/// `@Bean`.
enum bean = "flint.context.annotation.Bean";
/// `@Import`.
enum import_ = "flint.context.annotation.Import";
/// `@Primary`.
enum primary = "flint.context.annotation.Primary";
/// `@Fallback`.
enum fallback = "flint.context.annotation.Fallback";
/// `@Lazy`.
enum lazy_ = "flint.context.annotation.Lazy";
/// `@DependsOn`.
enum dependsOn = "flint.context.annotation.DependsOn";
/// `@Scope`.
enum scope_ = "flint.context.annotation.Scope";
/// `@Profile`.
enum profile = "flint.context.annotation.Profile";
/// `@Order`.
enum order = "flint.core.annotation.Order";

/// `@Autowired`.
enum autowired = "flint.beans.factory.annotation.Autowired";
/// `@Qualifier`.
enum qualifier = "flint.beans.factory.annotation.Qualifier";
/// `@Value`.
enum value = "flint.beans.factory.annotation.Value";
/// `@Inject`.
enum inject = "flint.jakarta.inject.Inject";

/// `@PostConstruct`.
enum postConstruct = "flint.jakarta.annotation.PostConstruct";
/// `@PreDestroy`.
enum preDestroy = "flint.jakarta.annotation.PreDestroy";
/// `InitializingBean`.
enum initializingBean = "flint.beans.factory.InitializingBean";
/// `DisposableBean`.
enum disposableBean = "flint.beans.factory.DisposableBean";

/// `@ConditionalOnProperty`.
enum onProperty = "flint.boot.autoconfigure.condition.ConditionalOnProperty";
/// `@ConditionalOnBooleanProperty`.
enum onBooleanProperty = "flint.boot.autoconfigure.condition.ConditionalOnBooleanProperty";
/// `@ConditionalOnBean`.
enum onBean = "flint.boot.autoconfigure.condition.ConditionalOnBean";
/// `@ConditionalOnMissingBean`.
enum onMissingBean = "flint.boot.autoconfigure.condition.ConditionalOnMissingBean";
/// `@ConditionalOnSingleCandidate`.
enum onSingleCandidate = "flint.boot.autoconfigure.condition.ConditionalOnSingleCandidate";
/// `@ConditionalOnClass`.
enum onClass = "flint.boot.autoconfigure.condition.ConditionalOnClass";
/// `@ConditionalOnMissingClass`.
enum onMissingClass = "flint.boot.autoconfigure.condition.ConditionalOnMissingClass";
/// `@ConditionalOnWebApplication`.
enum onWebApplication = "flint.boot.autoconfigure.condition.ConditionalOnWebApplication";
/// `@ConditionalOnNotWebApplication`.
enum onNotWebApplication = "flint.boot.autoconfigure.condition.ConditionalOnNotWebApplication";
/// ADR-028's `@ConditionalOnConfig`, read as a property condition.
enum onConfig = "flint.di.internal.conditions.ConditionalOnConfig";

/// `@RequestMapping`.
enum requestMapping = "flint.web.bind.annotation.RequestMapping";
/// `@ResponseBody`.
enum responseBody = "flint.web.bind.annotation.ResponseBody";
/// `@ResponseStatus`.
enum responseStatus = "flint.web.bind.annotation.ResponseStatus";
/// `@ControllerAdvice`.
enum controllerAdvice = "flint.web.bind.annotation.ControllerAdvice";
/// `@ExceptionHandler`.
enum exceptionHandler = "flint.web.bind.annotation.ExceptionHandler";
/// `@PathVariable`.
enum pathVariable = "flint.web.bind.annotation.PathVariable";
/// `@RequestParam`.
enum requestParam = "flint.web.bind.annotation.RequestParam";
/// `@RequestHeader`.
enum requestHeader = "flint.web.bind.annotation.RequestHeader";
/// `@RequestBody`.
enum requestBody = "flint.web.bind.annotation.RequestBody";
/// `@CookieValue`.
enum cookieValue = "flint.web.bind.annotation.CookieValue";
/// `@ModelAttribute`.
enum modelAttribute = "flint.web.bind.annotation.ModelAttribute";
/// `@Valid`.
enum valid = "flint.jakarta.validation.Valid";
/// `@Validated`.
enum validated = "flint.validation.annotation.Validated";

/// `@EventListener`.
enum eventListener = "flint.context.event.EventListener";
/// `@ConfigurationProperties`.
enum configurationProperties = "flint.boot.context.properties.ConfigurationProperties";
/// `@EnableConfigurationProperties`.
enum enableConfigurationProperties = "flint.boot.context.properties.EnableConfigurationProperties";

/// `@Id`.
enum id = "flint.data.annotation.Id";
/// `@Transient`.
enum transient = "flint.data.annotation.Transient";
/// `@Table`.
enum table = "flint.data.relational.core.mapping.Table";
/// `@Column`.
enum column = "flint.data.relational.core.mapping.Column";
/// `@Query`.
enum query = "flint.data.repository.Query";
/// `Repository<T, ID>`.
enum repository = "flint.data.repository.Repository";
/// `@JsonProperty`.
enum jsonProperty = "flint.jackson.annotation.JsonProperty";

/// `@Async`.
enum async_ = "flint.scheduling.annotation.Async";

/// Advice annotations: a bean with any of them on a public method, or on its class, is proxied.
immutable string[] adviceAnnotations = [
    "flint.transaction.annotation.Transactional", "flint.cache.annotation.Cacheable",
    "flint.cache.annotation.CachePut", "flint.cache.annotation.CacheEvict",
    "flint.cache.annotation.Caching", async_, validated, "flint.security.access.prepost.PreAuthorize",
    "flint.security.access.prepost.PostAuthorize", "flint.resilience.annotation.Retryable",
    "flint.resilience.annotation.ConcurrencyLimit"
];

/// Types the runtime registers itself, so injecting them needs no definition.
immutable string[] infrastructureTypes = [
    "flint.core.env.Environment", "flint.core.env.ConfigurableEnvironment",
    "flint.context.ApplicationContext", "flint.context.ConfigurableApplicationContext",
    "flint.beans.factory.BeanFactory", "flint.beans.factory.ListableBeanFactory",
    "flint.context.ApplicationEventPublisher", "flint.core.io.ResourceLoader",
    "flint.core.convert.ConversionService", "flint.engine.aot.bean.BeanFactory"
];

/// Parameter types the MVC runtime resolves by type.
immutable string[] resolvedByType = [
    "HttpServletRequest", "HttpServletResponse", "HttpHeaders", "Principal", "Locale",
    "UriComponentsBuilder", "BindingResult", "Errors", "Model", "WebRequest", "HttpSession"
];

/// `Introspector.decapitalize`: lower the first letter unless the first two are upper case (`URLService`).
string beanName(string simpleName)
{
    import std.ascii : isUpper, toLower;

    if (simpleName.length == 0)
        return simpleName;
    if (simpleName.length > 1 && isUpper(simpleName[0]) && isUpper(simpleName[1]))
        return simpleName;
    return toLower(simpleName[0]) ~ simpleName[1 .. $];
}

/// The extern(C) entry point of a generated module: each segment prefixed with its length.
string entryPoint(string moduleName)
{
    import std.algorithm.iteration : splitter;
    import std.conv : to;

    string name = "flint_aot_register_";
    foreach (segment; moduleName.splitter('.'))
        name ~= segment.length.to!string ~ segment;
    return name;
}

/// The package of a module: everything before its last dot, or empty.
string packageOf(string moduleName)
{
    import std.string : lastIndexOf;

    const dot = moduleName.lastIndexOf('.');
    return dot < 0 ? null : moduleName[0 .. dot];
}

/// Whether `moduleName` lies in package `name` (or is that module).
bool inPackage(string moduleName, string name)
{
    return name.length == 0 || moduleName == name || (moduleName.length > name.length
            && moduleName[0 .. name.length] == name && moduleName[name.length] == '.');
}
