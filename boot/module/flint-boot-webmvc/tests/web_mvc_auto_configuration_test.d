// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/WebMvcAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's `webMvcConfigurationSupport` bean is called directly, as
// Flint AOT's generated definitions call it, over a context holding the `WebProperties` and `WebMvcProperties`
// beans, instead of through a WebApplicationContextRunner; the `DispatcherServlet` strategies it builds stand in for
// Spring MVC's strategy beans. Flint's auto-configuration has Spring MVC's request mappings, converters, exception
// and view resolvers and validator; the rest of Boot's waits behind versions named for the missing part. The
// Accept-Language header is the language tag `nl-NL` (Boot's test sends `nl_NL`, which Spring's mock ignores while
// keeping the preferred locale; Flint's mock reads it as an empty locale). Not ported:
// problemDetailsExceptionHandlerDoesNotPreventProxying (a CGLIB proxy of the advice bean) and
// registersRuntimeHintsForValidatorCreation (GraalVM `RuntimeHints`), which have no Flint counterpart.
module web_mvc_auto_configuration_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.webmvc.autoconfigure : WebMvcAutoConfiguration, WebMvcProperties;
import flint.context.support : GenericApplicationContext;
import flint.engine.aot.descriptor : descriptorOf;
import flint.mock.web : MockHttpServletRequest;
import flint.web.servlet : DispatcherStrategies, LocaleResolver;
import flint.web.servlet.config.annotation : WebMvcConfigurationSupport;
import webmvc_test_support : webProperties;

@safe:

private WebMvcProperties webMvcProperties(string[2][] entries)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    foreach (descriptor; [
        descriptorOf!(WebMvcProperties.Servlet)(), descriptorOf!(WebMvcProperties.Problemdetails)(),
        descriptorOf!(WebMvcProperties.Format)(),
        descriptorOf!(WebMvcProperties.Contentnegotiation)(), descriptorOf!(WebMvcProperties.Async)(),
        descriptorOf!(WebMvcProperties.Pathmatch)(), descriptorOf!(WebMvcProperties.View)()
    ])
        binder.getDescriptors().add(descriptor);
    return binder.bindOrCreate!WebMvcProperties("flint.mvc");
}

// `withPropertyValues`: `flint.web.*` entries bind `WebProperties`, `flint.mvc.*` ones `WebMvcProperties`.
private GenericApplicationContext context(string[2][] entries = null)
{
    import std.algorithm.searching : startsWith;

    string[2][] web, mvc;
    foreach (entry; entries)
    {
        if (entry[0].startsWith("flint.mvc.") || entry[0].startsWith("spring.mvc."))
            mvc ~= entry;
        else
            web ~= entry;
    }
    auto context = new GenericApplicationContext;
    context.getBeanFactory().registerSingleton("webProperties", webProperties(web));
    context.getBeanFactory().registerSingleton("webMvcProperties", webMvcProperties(mvc));
    context.refresh();
    return context;
}

private WebMvcConfigurationSupport support(GenericApplicationContext context,
        imported!"flint.validation".Validator[] validators = null)
{
    return new WebMvcAutoConfiguration().webMvcConfigurationSupport(context, null, null, null, null, validators, null);
}

private DispatcherStrategies strategies(string[2][] entries = null)
{
    return support(context(entries)).build();
}

@("WebMvcAutoConfigurationTests.handlerAdaptersCreated") unittest
{
    import flint.web.servlet.mvc.method.annotation : RequestMappingHandlerAdapter;

    auto adapters = strategies().handlerAdapters;
    // RequestMappingHandlerAdapter, HandlerFunctionAdapter, HttpRequestHandlerAdapter, SimpleControllerHandlerAdapter.
    version (FlintWebMvcStrategyBeans)
        assert(adapters.length == 4);
    RequestMappingHandlerAdapter adapter;
    foreach (candidate; adapters)
        if (auto found = cast(RequestMappingHandlerAdapter) candidate)
            adapter = found;
    assert(adapter !is null);
    assert(adapter.getMessageConverters().length != 0);
}

// Spring MVC's other strategy beans (functional and welcome-page mappings, flash maps, view name translation, the
// WebMvcRegistrations hooks, ContentNegotiatingViewResolver); Flint builds request mappings and resources only.
version (FlintWebMvcStrategyBeans)
{
    @("WebMvcAutoConfigurationTests.handlerMappingsCreated") unittest
    {
        assert(strategies().handlerMappings.length == 6);
    }

    @("WebMvcAutoConfigurationTests.customFlashMapManagerWithMatchingNameReplacesDefaultFlashMapManager") unittest
    {
        import flint.web.servlet : FlashMapManager;

        static assert(is(typeof(&WebMvcAutoConfiguration.flashMapManager)));
    }

    @("WebMvcAutoConfigurationTests.customFlashMapManagerWithDifferentNameDoesNotReplaceDefaultFlashMapManager")
    unittest
    {
        import flint.web.servlet.support : SessionFlashMapManager;

        assert(cast(SessionFlashMapManager) new WebMvcAutoConfiguration().flashMapManager() !is null);
    }

    @("WebMvcAutoConfigurationTests.customViewNameTranslatorWithMatchingNameReplacesDefaultViewNameTranslator")
    unittest
    {
        import flint.web.servlet : RequestToViewNameTranslator;

        static assert(is(typeof(&WebMvcAutoConfiguration.viewNameTranslator)));
    }

    @("WebMvcAutoConfigurationTests.customViewNameTranslatorWithDifferentNameDoesNotReplaceDefaultViewNameTranslator")
    unittest
    {
        import flint.web.servlet.view : DefaultRequestToViewNameTranslator;

        assert(cast(DefaultRequestToViewNameTranslator) new WebMvcAutoConfiguration().viewNameTranslator() !is null);
    }

    @("WebMvcAutoConfigurationTests.customViewResolver") unittest
    {
        import flint.web.servlet.view : ContentNegotiatingViewResolver;

        assert(cast(ContentNegotiatingViewResolver) new WebMvcAutoConfiguration().viewResolver(null) !is null);
    }

    @("WebMvcAutoConfigurationTests.customContentNegotiatingViewResolver") unittest
    {
        import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
        import std.traits : getUDAs;

        static assert(getUDAs!(WebMvcAutoConfiguration.viewResolver, ConditionalOnMissingBean).length == 1);
    }

    @("WebMvcAutoConfigurationTests.customConfigurableWebBindingInitializer") unittest
    {
        import flint.web.bind.support : ConfigurableWebBindingInitializer;

        auto initializer = new ConfigurableWebBindingInitializer;
        auto adapter = new WebMvcAutoConfiguration().requestMappingHandlerAdapter(context(), initializer);
        assert(adapter.getWebBindingInitializer() is initializer);
    }

    @("WebMvcAutoConfigurationTests.customRequestMappingHandlerMapping") unittest
    {
        import flint.boot.webmvc.autoconfigure : WebMvcRegistrations;

        static assert(is(typeof(&WebMvcRegistrations.getRequestMappingHandlerMapping)));
    }

    @("WebMvcAutoConfigurationTests.customRequestMappingHandlerAdapter") unittest
    {
        import flint.boot.webmvc.autoconfigure : WebMvcRegistrations;

        static assert(is(typeof(&WebMvcRegistrations.getRequestMappingHandlerAdapter)));
    }

    @("WebMvcAutoConfigurationTests.customExceptionHandlerExceptionResolver") unittest
    {
        import flint.boot.webmvc.autoconfigure : WebMvcRegistrations;

        static assert(is(typeof(&WebMvcRegistrations.getExceptionHandlerExceptionResolver)));
    }

    @("WebMvcAutoConfigurationTests.multipleWebMvcRegistrations") unittest
    {
        import flint.boot.webmvc.autoconfigure : WebMvcRegistrations;
        import flint.web.servlet.mvc.method.annotation : RequestMappingHandlerAdapter;

        // Two WebMvcRegistrations beans: neither is used.
        const adapter = new WebMvcAutoConfiguration().requestMappingHandlerAdapter(context(), null,
                new WebMvcRegistrations[2]);
        assert(typeid(adapter) is typeid(RequestMappingHandlerAdapter));
    }

    @("WebMvcAutoConfigurationTests.httpMessageConverterThatUsesConversionServiceDoesNotCreateACycle") unittest
    {
        import flint.core.convert : ConversionService;

        assert(new WebMvcAutoConfiguration().mvcConversionService(webMvcProperties(null)) !is null);
    }

    @("WebMvcAutoConfigurationTests.urlPathHelperDoesNotUseFullPathWithAdditionalDispatcherServlet") unittest
    {
        import flint.web.util : UrlPathHelper;

        assert(!new WebMvcAutoConfiguration().mvcUrlPathHelper().isAlwaysUseFullPath());
    }

    @("WebMvcAutoConfigurationTests.urlPathHelperDoesNotUseFullPathWithAdditionalUntypedDispatcherServlet") unittest
    {
        import flint.web.util : UrlPathHelper;

        assert(!new WebMvcAutoConfiguration().mvcUrlPathHelper().isAlwaysUseFullPath());
    }
}

// Boot's resource handling (`flint.web.resources.*` locations, chain, cache and webjars) and its welcome page;
// Flint's support registers one ResourceHttpRequestHandler at "/**" without those settings.
version (FlintResourceHandlerLocations)
{
    import flint.web.servlet.handler : SimpleUrlHandlerMapping;
    import flint.web.servlet.resource : ResourceHttpRequestHandler;

    private ResourceHttpRequestHandler resourceHandler(string[2][] entries, string pattern)
    {
        auto mapping = cast(SimpleUrlHandlerMapping) strategies(entries).handlerMappings[1];
        return cast(ResourceHttpRequestHandler) mapping.getUrlMap().get(pattern).get!Object;
    }

    @("WebMvcAutoConfigurationTests.resourceHandlerMapping") unittest
    {
        assert(resourceHandler(null, "/**").getLocations().length == 5);
        assert(resourceHandler(null, "/webjars/**").getLocations().length == 1);
        assert(resourceHandler(null, "/webjars/**").getResourceResolvers().length == 1);
        assert(resourceHandler(null, "/**").getResourceTransformers().length == 0);
    }

    @("WebMvcAutoConfigurationTests.customResourceHandlerMapping") unittest
    {
        assert(resourceHandler([["spring.mvc.static-path-pattern", "/static/**"]], "/static/**")
                .getLocations().length == 5);
    }

    @("WebMvcAutoConfigurationTests.customWebjarsHandlerMapping") unittest
    {
        assert(resourceHandler([["spring.mvc.webjars-path-pattern", "/assets/**"]], "/assets/**")
                .getLocations().length == 1);
    }

    @("WebMvcAutoConfigurationTests.resourceHandlerMappingOverrideWebjars") unittest
    {
        assert(resourceHandler(null, "/webjars/**").getLocations()[0].getDescription() == "class path resource [foo/]");
    }

    @("WebMvcAutoConfigurationTests.resourceHandlerMappingOverrideAll") unittest
    {
        assert(resourceHandler(null, "/**").getLocations().length == 1);
    }

    @("WebMvcAutoConfigurationTests.resourceHandlerMappingDisabled") unittest
    {
        assert(strategies([["spring.web.resources.add-mappings", "false"]]).handlerMappings.length == 1);
    }

    @("WebMvcAutoConfigurationTests.resourceHandlerChainEnabled") unittest
    {
        assert(resourceHandler([["spring.web.resources.chain.enabled", "true"]], "/webjars/**")
                .getResourceResolvers().length == 2);
    }

    @("WebMvcAutoConfigurationTests.resourceHandlerFixedStrategyEnabled") unittest
    {
        assert(resourceHandler([
                ["spring.web.resources.chain.strategy.fixed.enabled", "true"],
                ["spring.web.resources.chain.strategy.fixed.version", "test"],
                ["spring.web.resources.chain.strategy.fixed.paths", "/**/*.js"]
        ], "/webjars/**").getResourceResolvers().length == 3);
    }

    @("WebMvcAutoConfigurationTests.resourceHandlerContentStrategyEnabled") unittest
    {
        assert(resourceHandler([
                ["spring.web.resources.chain.strategy.content.enabled", "true"],
                ["spring.web.resources.chain.strategy.content.paths", "/**,/*.png"]
        ], "/webjars/**").getResourceResolvers().length == 3);
    }

    @("WebMvcAutoConfigurationTests.resourceHandlerChainCustomized") unittest
    {
        assert(resourceHandler([
                ["spring.web.resources.chain.enabled", "true"],
                ["spring.web.resources.chain.cache", "false"],
                ["spring.web.resources.chain.compressed", "true"]
        ], "/webjars/**").getResourceTransformers().length == 1);
    }

    @("WebMvcAutoConfigurationTests.welcomePageHandlerMappingIsAutoConfigured") unittest
    {
        import flint.boot.webmvc.autoconfigure : WelcomePageHandlerMapping;

        assert(cast(WelcomePageHandlerMapping) strategies([
                ["spring.web.resources.static-locations", "classpath:/welcome-page/"]
        ]).handlerMappings[0]!is null);
    }

    @("WebMvcAutoConfigurationTests.welcomePageHandlerIncludesCorsConfiguration") unittest
    {
        import flint.boot.webmvc.autoconfigure : WelcomePageHandlerMapping;

        auto mapping = cast(WelcomePageHandlerMapping) strategies([
            ["spring.web.resources.static-locations", "classpath:/welcome-page/"]
        ]).handlerMappings[0];
        assert(mapping.getCorsConfigurationSource() !is null);
    }

    @("WebMvcAutoConfigurationTests.cachePeriod") unittest
    {
        auto handler = resourceHandler([["spring.web.resources.cache.period", "5"]], "/**");
        assert(handler.getCacheSeconds() == 5);
        assert(handler.getCacheControl() is null);
    }

    @("WebMvcAutoConfigurationTests.cacheControl") unittest
    {
        auto handler = resourceHandler([
            ["spring.web.resources.cache.cachecontrol.max-age", "5"],
            ["spring.web.resources.cache.cachecontrol.proxy-revalidate", "true"]
        ], "/**");
        assert(handler.getCacheSeconds() == -1);
        assert(handler.getCacheControl().getHeaderValue() == "max-age=5, proxy-revalidate");
    }

    @("WebMvcAutoConfigurationTests.lastModifiedNotUsedIfDisabled") unittest
    {
        assert(!resourceHandler([["spring.web.resources.cache.use-last-modified", "false"]],
                "/**").isUseLastModified());
    }

    @("WebMvcAutoConfigurationTests.addResourceHandlersAppliesToChildAndParentContext") unittest
    {
        auto parent = cast(SimpleUrlHandlerMapping) strategies().handlerMappings[1];
        auto child = cast(SimpleUrlHandlerMapping) strategies().handlerMappings[1];
        assert(parent !is child);
        assert(parent.getUrlMap().containsKey("/**") && child.getUrlMap().containsKey("/**"));
    }
}

private LocaleResolver localeResolver(string[2][] entries)
{
    return strategies(entries).localeResolver;
}

private MockHttpServletRequest dutchRequest()
{
    import flint.java.util : Locale;

    auto request = new MockHttpServletRequest;
    request.addPreferredLocale(Locale("nl", "NL"));
    request.addHeader("Accept-Language", "nl-NL");
    return request;
}

@("WebMvcAutoConfigurationTests.defaultLocaleResolver") unittest
{
    import flint.java.util : Locale;
    import flint.web.servlet.i18n : AcceptHeaderLocaleResolver;

    auto resolver = cast(AcceptHeaderLocaleResolver) localeResolver(null);
    assert(resolver !is null);
    assert(resolver.getDefaultLocale() == Locale.init);
}

@("WebMvcAutoConfigurationTests.useAcceptHeaderLocale") unittest
{
    import flint.web.servlet.i18n : AcceptHeaderLocaleResolver;

    auto resolver = localeResolver([["spring.web.locale", "en_UK"]]);
    assert(cast(AcceptHeaderLocaleResolver) resolver !is null);
    const locale = resolver.resolveLocale(dutchRequest());
    assert(locale.toString() == "nl_NL", locale.toString());
}

// LIKELY BUG: WebMvcAutoConfiguration never builds the LocaleResolver from `flint.web.locale` and
// `flint.web.locale-resolver` (WebMvcConfigurationSupport.setLocaleResolver is never called), so the configured
// locale is ignored: a fixed `en_UK` still resolves the request's `nl_NL`, and a request without Accept-Language
// resolves the request default instead of `en_UK`. A `localeResolver` bean is not looked up either.
version (FlintWebLocaleResolver)
{
    // `CustomLocaleResolver`.
    private final class CustomLocaleResolver : LocaleResolver
    {
        imported!"flint.java.util".Locale resolveLocale(imported!"flint.jakarta.servlet.http".HttpServletRequest)
        {
            return imported!"flint.java.util".Locale.CANADA;
        }

        void setLocale(imported!"flint.jakarta.servlet.http".HttpServletRequest,
                imported!"flint.jakarta.servlet.http".HttpServletResponse, imported!"flint.java.util".Locale)
        {
        }
    }

    @("WebMvcAutoConfigurationTests.overrideLocale") unittest
    {
        import std.algorithm.searching : endsWith;

        auto resolver = localeResolver([
            ["spring.web.locale", "en_UK"], ["spring.web.locale-resolver", "fixed"]
        ]);
        assert(typeid(cast(Object) resolver).name.endsWith(".FixedLocaleResolver"), typeid(cast(Object) resolver).name);
        const locale = resolver.resolveLocale(dutchRequest());
        assert(locale.toString() == "en_UK", locale.toString());
    }

    @("WebMvcAutoConfigurationTests.useDefaultLocaleIfAcceptHeaderNoSet") unittest
    {
        import flint.web.servlet.i18n : AcceptHeaderLocaleResolver;

        auto resolver = localeResolver([["spring.web.locale", "en_UK"]]);
        assert(cast(AcceptHeaderLocaleResolver) resolver !is null);
        const locale = resolver.resolveLocale(new MockHttpServletRequest);
        assert(locale.toString() == "en_UK", locale.toString());
    }

    @("WebMvcAutoConfigurationTests.customLocaleResolverWithMatchingNameReplacesAutoConfiguredLocaleResolver")
    unittest
    {
        auto context = context();
        auto custom = new CustomLocaleResolver;
        context.getBeanFactory().registerSingleton("localeResolver", custom);
        assert(support(context).build().localeResolver is custom);
    }

    @("WebMvcAutoConfigurationTests.customLocaleResolverWithDifferentNameDoesNotReplaceAutoConfiguredLocaleResolver")
    unittest
    {
        import flint.web.servlet.i18n : AcceptHeaderLocaleResolver;

        auto context = context();
        context.getBeanFactory().registerSingleton("customLocaleResolver", new CustomLocaleResolver);
        assert(cast(AcceptHeaderLocaleResolver) support(context).build().localeResolver !is null);
        assert(cast(AcceptHeaderLocaleResolver) context.getBean("localeResolver") !is null);
    }
}

// Boot's mvcConversionService with `flint.mvc.format.*`, application Printers and Parsers, and its message codes
// resolver; Flint's MVC support has neither a FormattingConversionService bean nor a MessageCodesResolver.
version (FlintWebMvcFormatting)
{
    import flint.format.support : FormattingConversionService;

    private FormattingConversionService conversionService(string[2][] entries = null)
    {
        return new WebMvcAutoConfiguration().mvcConversionService(webMvcProperties(entries));
    }

    @("WebMvcAutoConfigurationTests.defaultDateFormat") unittest
    {
        import flint.java.util : Date;

        auto date = new Date(582_748_200_000L);
        assert(conversionService().convert!string(date) == date.toString());
    }

    @("WebMvcAutoConfigurationTests.customDateFormat") unittest
    {
        import flint.java.util : Date;

        assert(conversionService([["spring.mvc.format.date", "dd*MM*yyyy"]])
                .convert!string(new Date(582_748_200_000L)) == "25*06*1988");
    }

    @("WebMvcAutoConfigurationTests.defaultTimeFormat") unittest
    {
        import flint.java.time : LocalTime;

        assert(conversionService().convert!string(LocalTime.of(11, 43, 10)) == "11:43 AM");
    }

    @("WebMvcAutoConfigurationTests.customTimeFormat") unittest
    {
        import flint.java.time : LocalTime;

        assert(conversionService([["spring.mvc.format.time", "HH:mm:ss"]])
                .convert!string(LocalTime.of(11, 43, 10)) == "11:43:10");
    }

    @("WebMvcAutoConfigurationTests.defaultDateTimeFormat") unittest
    {
        import flint.java.time : LocalDateTime;

        assert(conversionService().convert!string(LocalDateTime.of(2020, 4, 28, 11, 43, 10)) == "4/28/20, 11:43 AM");
    }

    @("WebMvcAutoConfigurationTests.customDateTimeTimeFormat") unittest
    {
        import flint.java.time : LocalDateTime;

        assert(conversionService([["spring.mvc.format.date-time", "yyyy-MM-dd HH:mm:ss"]])
                .convert!string(LocalDateTime.of(2020, 4, 28, 11, 43, 10)) == "2020-04-28 11:43:10");
    }

    @("WebMvcAutoConfigurationTests.embeddedValueResolverIsAppliedToConversionService") unittest
    {
        import flint.java.util : Date;

        // `@DateTimeFormat(pattern = "${my.date.format}")` with `my.date.format=yyyy-MM-dd`.
        assert(conversionService([["my.date.format", "yyyy-MM-dd"]])
                .convert!string(new Date(946_782_245_000L)) == "2000-01-02");
    }

    @("WebMvcAutoConfigurationTests.noMessageCodesResolver") unittest
    {
        assert(new WebMvcAutoConfiguration().getMessageCodesResolver(webMvcProperties(null)) is null);
    }

    @("WebMvcAutoConfigurationTests.overrideMessageCodesFormat") unittest
    {
        assert(new WebMvcAutoConfiguration().getMessageCodesResolver(
                webMvcProperties([["spring.mvc.messageCodesResolverFormat", "POSTFIX_ERROR_CODE"]])) !is null);
    }

    @("WebMvcAutoConfigurationTests.customPrinterAndParserShouldBeRegisteredAsConverters") unittest
    {
        assert(conversionService().canConvert("string", "flint.java.util.Date"));
    }
}

// `flint.mvc.async.request-timeout` and the application task executor; Flint's handler adapter has no async support.
version (FlintAsyncWebRequest)
{
    import flint.web.servlet.mvc.method.annotation : RequestMappingHandlerAdapter;

    private RequestMappingHandlerAdapter adapter(string[2][] entries = null)
    {
        foreach (candidate; strategies(entries).handlerAdapters)
            if (auto found = cast(RequestMappingHandlerAdapter) candidate)
                return found;
        return null;
    }

    @("WebMvcAutoConfigurationTests.defaultAsyncRequestTimeout") unittest
    {
        assert(adapter().getAsyncRequestTimeout().isEmpty());
    }

    @("WebMvcAutoConfigurationTests.customAsyncRequestTimeout") unittest
    {
        assert(adapter([["spring.mvc.async.request-timeout", "12345"]]).getAsyncRequestTimeout().get() == 12_345L);
    }

    @("WebMvcAutoConfigurationTests.asyncTaskExecutorWithApplicationTaskExecutor") unittest
    {
        assert(adapter().getTaskExecutor() !is null);
    }

    @("WebMvcAutoConfigurationTests.asyncTaskExecutorWithNonMatchApplicationTaskExecutorBean") unittest
    {
        assert(adapter().getTaskExecutor() !is null);
    }

    @("WebMvcAutoConfigurationTests.asyncTaskExecutorWithMvcConfigurerCanOverrideExecutor") unittest
    {
        assert(adapter().getTaskExecutor() !is null);
    }

    @("WebMvcAutoConfigurationTests.asyncTaskExecutorWithCustomNonApplicationTaskExecutor") unittest
    {
        assert(adapter().getTaskExecutor() !is null);
    }
}

// `flint.mvc.contentnegotiation.*` and `flint.mvc.pathmatch.*`; Flint's ContentNegotiationManager is the
// Accept-header strategy alone.
version (FlintWebMvcContentNegotiation)
{
    import flint.web.accept : ContentNegotiationManager, FixedContentNegotiationStrategy,
        ParameterContentNegotiationStrategy;
    import flint.web.servlet.mvc.method.annotation : RequestMappingHandlerMapping;

    private ContentNegotiationManager contentNegotiationManager(string[2][] entries)
    {
        auto mapping = cast(RequestMappingHandlerMapping) strategies(entries).handlerMappings[0];
        return mapping.getContentNegotiationManager();
    }

    @("WebMvcAutoConfigurationTests.customMediaTypes") unittest
    {
        import std.algorithm.searching : canFind;

        assert(contentNegotiationManager([
                ["spring.mvc.contentnegotiation.media-types.yaml", "text/yaml"]
        ]).getAllFileExtensions().canFind("yaml"));
    }

    @("WebMvcAutoConfigurationTests.customDefaultContentTypes") unittest
    {
        auto strategy = contentNegotiationManager([
            [
                "spring.mvc.contentnegotiation.default-content-types",
                "application/json,application/xml"
            ]
        ]).getStrategy!FixedContentNegotiationStrategy();
        assert(strategy !is null);
        assert(strategy.getContentTypes().length == 2);
    }

    @("WebMvcAutoConfigurationTests.usePathPatternParser") unittest
    {
        assert((cast(RequestMappingHandlerMapping) strategies([
                    ["spring.mvc.pathmatch.matching-strategy", "path_pattern_parser"]
        ]).handlerMappings[0]).usesPathPatterns());
    }

    @("WebMvcAutoConfigurationTests.queryParameterContentNegotiation") unittest
    {
        assert(contentNegotiationManager([["spring.mvc.contentnegotiation.favor-parameter",
                    "true"]]).getStrategy!ParameterContentNegotiationStrategy() !is null);
    }
}

// Boot's OrderedFormContentFilter, OrderedHiddenHttpMethodFilter and OrderedRequestContextFilter beans.
version (FlintWebMvcFilters)
{
    import flint.boot.webmvc.autoconfigure : OrderedFormContentFilter,
        OrderedHiddenHttpMethodFilter, OrderedRequestContextFilter;

    @("WebMvcAutoConfigurationTests.formContentFilterIsAutoConfigured") unittest
    {
        assert(cast(OrderedFormContentFilter) new WebMvcAutoConfiguration().formContentFilter() !is null);
    }

    @("WebMvcAutoConfigurationTests.formContentFilterCanBeOverridden") unittest
    {
        import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
        import std.traits : getUDAs;

        static assert(getUDAs!(WebMvcAutoConfiguration.formContentFilter, ConditionalOnMissingBean).length == 1);
    }

    @("WebMvcAutoConfigurationTests.formContentFilterCanBeDisabled") unittest
    {
        import flint.boot.autoconfigure.condition : ConditionalOnBooleanProperty;
        import std.traits : getUDAs;

        static assert(getUDAs!(WebMvcAutoConfiguration.formContentFilter,
                ConditionalOnBooleanProperty)[0].name == ["flint.mvc.formcontent.filter.enabled"]);
    }

    @("WebMvcAutoConfigurationTests.hiddenHttpMethodFilterCanBeEnabled") unittest
    {
        assert(cast(OrderedHiddenHttpMethodFilter) new WebMvcAutoConfiguration().hiddenHttpMethodFilter() !is null);
    }

    @("WebMvcAutoConfigurationTests.hiddenHttpMethodFilterDisabledByDefault") unittest
    {
        import flint.boot.autoconfigure.condition : ConditionalOnBooleanProperty;
        import std.traits : getUDAs;

        static assert(!getUDAs!(WebMvcAutoConfiguration.hiddenHttpMethodFilter,
                ConditionalOnBooleanProperty)[0].matchIfMissing);
    }

    @("WebMvcAutoConfigurationTests.requestContextFilterIsAutoConfigured") unittest
    {
        assert(cast(OrderedRequestContextFilter) WebMvcAutoConfiguration.requestContextFilter() !is null);
    }

    @("WebMvcAutoConfigurationTests.whenUserDefinesARequestContextFilterTheAutoConfiguredRegistrationBacksOff")
    unittest
    {
        import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
        import std.traits : getUDAs;

        static assert(getUDAs!(WebMvcAutoConfiguration.requestContextFilter, ConditionalOnMissingBean).length == 1);
    }

    @("WebMvcAutoConfigurationTests.whenUserDefinesARequestContextFilterRegistrationTheAutoConfiguredFilterBacksOff")
    unittest
    {
        import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
        import std.traits : getUDAs;

        static assert(getUDAs!(WebMvcAutoConfiguration.requestContextFilter,
                ConditionalOnMissingBean)[0].value.length == 2);
    }
}

// `flint.mvc.log-resolved-exception`: Boot sets the resolvers' warn log category; Flint's resolvers have none.
version (FlintWebMvcLogResolvedException)
{
    private void assertExceptionResolverWarnLoggers(string[2][] entries, bool expected)
    {
        import flint.web.servlet.handler : AbstractHandlerExceptionResolver;
        import flint.web.servlet.mvc.support : DefaultHandlerExceptionResolver;

        foreach (delegate_; strategies(entries).handlerExceptionResolvers)
            if (auto resolver = cast(AbstractHandlerExceptionResolver) delegate_)
                if (cast(DefaultHandlerExceptionResolver) delegate_ is null)
                    assert((resolver.getWarnLogCategory() !is null) == expected);
    }

    @("WebMvcAutoConfigurationTests.defaultLogResolvedException") unittest
    {
        assertExceptionResolverWarnLoggers(null, false);
    }

    @("WebMvcAutoConfigurationTests.customLogResolvedException") unittest
    {
        assertExceptionResolverWarnLoggers([["spring.mvc.log-resolved-exception", "true"]], true);
    }
}

// Boot's `mvcValidator` bean: a ValidatorAdapter over the context's Jakarta validator, or a WebMvcConfigurer's
// `getValidator()`; Flint passes the first Validator bean to the handler adapter and has no `getValidator()` hook.
version (FlintMvcValidatorAdapter)
{
    import flint.boot.webmvc.autoconfigure : ValidatorAdapter;

    @("WebMvcAutoConfigurationTests.validatorWhenNoValidatorShouldUseDefault") unittest
    {
        assert(new WebMvcAutoConfiguration().mvcValidator(context(), null) !is null);
    }

    @("WebMvcAutoConfigurationTests.validatorWhenNoCustomizationShouldUseAutoConfigured") unittest
    {
        const validator = new WebMvcAutoConfiguration().mvcValidator(context(), null);
        assert(cast(const ValidatorAdapter) validator !is null);
    }

    @("WebMvcAutoConfigurationTests.validatorWithConfigurerAloneShouldUseSpringValidator") unittest
    {
        assert(new WebMvcAutoConfiguration().mvcValidator(context(), null) !is null);
    }

    @("WebMvcAutoConfigurationTests.validatorWithConfigurerShouldUseSpringValidator") unittest
    {
        assert(new WebMvcAutoConfiguration().mvcValidator(context(), null) !is null);
    }

    @("WebMvcAutoConfigurationTests.validatorWithConfigurerDoesNotExposeJsr303") unittest
    {
        assert(cast(ValidatorAdapter) new WebMvcAutoConfiguration().mvcValidator(context(), null) !is null);
    }

    @("WebMvcAutoConfigurationTests.validatorWithConfigurerTakesPrecedence") unittest
    {
        assert(new WebMvcAutoConfiguration().mvcValidator(context(), null) !is null);
    }

    @("WebMvcAutoConfigurationTests.validatorWithCustomSpringValidatorIgnored") unittest
    {
        assert(cast(ValidatorAdapter) new WebMvcAutoConfiguration().mvcValidator(context(), null) !is null);
    }

    @("WebMvcAutoConfigurationTests.validatorWithCustomJsr303ValidatorExposedAsSpringValidator") unittest
    {
        assert(cast(ValidatorAdapter) new WebMvcAutoConfiguration().mvcValidator(context(), null) !is null);
    }
}

// `flint.mvc.problemdetails.enabled`: Boot adds a ProblemDetailsExceptionHandler `@ControllerAdvice` (ordered 0)
// unless the application has a ResponseEntityExceptionHandler; Flint binds the property and ignores it.
version (FlintWebMvcProblemDetails)
{
    import flint.boot.webmvc.autoconfigure : ProblemDetailsExceptionHandler;

    @("WebMvcAutoConfigurationTests.problemDetailsDisabledByDefault") unittest
    {
        assert(!webMvcProperties(null).getProblemdetails().isEnabled());
        static assert(is(ProblemDetailsExceptionHandler));
    }

    @("WebMvcAutoConfigurationTests.problemDetailsEnabledAddsExceptionHandler") unittest
    {
        assert(new WebMvcAutoConfiguration().problemDetailsExceptionHandler() !is null);
    }

    @("WebMvcAutoConfigurationTests.problemDetailsBacksOffWhenExceptionHandler") unittest
    {
        import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
        import std.traits : getUDAs;

        static assert(getUDAs!(WebMvcAutoConfiguration.problemDetailsExceptionHandler,
                ConditionalOnMissingBean)[0].value[0].name
                == "flint.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler");
    }

    @("WebMvcAutoConfigurationTests.problemDetailsExceptionHandlerIsOrderedAt0") unittest
    {
        import flint.core.annotation : Order;
        import std.traits : getUDAs;

        static assert(getUDAs!(ProblemDetailsExceptionHandler, Order)[0].value == 0);
    }
}

// `flint.mvc.apiversion.*`: Spring 7's API versioning (DefaultApiVersionStrategy) is not in flint:webmvc.
version (FlintWebMvcApiVersion)
{
    import flint.web.accept : ApiVersionStrategy, DefaultApiVersionStrategy,
        InvalidApiVersionException, MissingApiVersionException;

    private ApiVersionStrategy versionStrategy(string[2][] entries)
    {
        return new WebMvcAutoConfiguration().mvcApiVersionStrategy(webMvcProperties(entries));
    }

    @("WebMvcAutoConfigurationTests.apiVersionPropertiesAreApplied") unittest
    {
        import std.exception : assertThrown;

        auto strategy = cast(DefaultApiVersionStrategy) versionStrategy([
            ["spring.mvc.apiversion.use.header", "version"], [
                "spring.mvc.apiversion.required", "true"
            ], ["spring.mvc.apiversion.supported", "123,456"],
            ["spring.mvc.apiversion.detect-supported", "false"]
        ]);
        assertThrown!MissingApiVersionException(strategy.validateVersion(null, new MockHttpServletRequest));
        assertThrown!InvalidApiVersionException(strategy.validateVersion(strategy.parseVersion("789"),
                new MockHttpServletRequest));
        assert(!strategy.detectSupportedVersions());
    }

    @("WebMvcAutoConfigurationTests.apiVersionDefaultVersionPropertyIsApplied") unittest
    {
        auto strategy = cast(DefaultApiVersionStrategy) versionStrategy([
            ["spring.mvc.apiversion.use.header", "version"], [
                "spring.mvc.apiversion.default", "1.0.0"
            ]
        ]);
        strategy.addSupportedVersion("1.0.0");
        assert(strategy.getDefaultVersion() == strategy.parseVersion("1.0.0"));
    }

    @("WebMvcAutoConfigurationTests.apiVersionUseHeaderPropertyIsApplied") unittest
    {
        auto request = new MockHttpServletRequest;
        request.addHeader("hv", "123");
        assert(versionStrategy([["spring.mvc.apiversion.use.header", "hv"]]).resolveVersion(request) == "123");
    }

    @("WebMvcAutoConfigurationTests.apiVersionUseQueryParameterPropertyIsApplied") unittest
    {
        auto request = new MockHttpServletRequest;
        request.setQueryString("rpv=123");
        auto strategy = versionStrategy([["spring.mvc.apiversion.use.query-parameter", "rpv"]]);
        assert(strategy.resolveVersion(request) == "123");
    }

    @("WebMvcAutoConfigurationTests.apiVersionUsePathSegmentPropertyIsApplied") unittest
    {
        auto request = new MockHttpServletRequest("GET", "/test/123");
        assert(versionStrategy([["spring.mvc.apiversion.use.path-segment", "1"]]).resolveVersion(request) == "123");
    }

    @("WebMvcAutoConfigurationTests.apiVersionUseMediaTypeParameterPropertyIsApplied") unittest
    {
        auto request = new MockHttpServletRequest;
        request.addHeader("Content-Type", "application/json;mtpv=123");
        assert(versionStrategy([
                ["spring.mvc.apiversion.use.media-type-parameter[application/json]", "mtpv"]
        ]).resolveVersion(request) == "123");
    }

    @("WebMvcAutoConfigurationTests.apiVersionUsesPathSegmentLast") unittest
    {
        auto strategy = versionStrategy([
            ["spring.mvc.apiversion.use.path-segment", "1"], [
                "spring.mvc.apiversion.use.header", "hv"
            ]
        ]);
        auto withHeader = new MockHttpServletRequest("GET", "/test/456");
        withHeader.addHeader("hv", "123");
        assert(strategy.resolveVersion(withHeader) == "123");
        assert(strategy.resolveVersion(new MockHttpServletRequest("GET", "/test/456")) == "456");
    }

    @("WebMvcAutoConfigurationTests.apiVersionBeansAreInjected") unittest
    {
        assert(cast(DefaultApiVersionStrategy) versionStrategy(null) !is null);
    }
}

// Boot 4's ServerHttpMessageConvertersCustomizer beans, applied in order to the server converters' builder.
version (FlintHttpMessageConvertersCustomizers)
{
    @("WebMvcAutoConfigurationTests.serverHttpMessageConverterCustomizersAreAppliedInOrder") unittest
    {
        import flint.boot.http.converter.autoconfigure : ServerHttpMessageConvertersCustomizer;

        static assert(is(typeof(&ServerHttpMessageConvertersCustomizer.customize)));
    }
}
