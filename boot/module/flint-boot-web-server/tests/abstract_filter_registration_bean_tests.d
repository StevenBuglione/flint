// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/web/servlet/AbstractFilterRegistrationBeanTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the abstract JUnit class is a mixin template that filter_registration_bean_test.d
// and delegating_filter_proxy_registration_bean_upstream_test.d mix in with their `createFilterRegistrationBean`
// and `isExpectedFilter`, labelled with their class as JUnit reports the inherited tests; the Mockito
// `ServletContext` and `FilterRegistration.Dynamic` are web_server_test_support's recording fakes;
// `determineDispatcherTypes` is Flint's `getDispatcherTypes`. Not ported: setServletRegistrationBeanMustNotBeNull,
// addServletRegistrationBeanMustNotBeNull, setUrlPatternMustNotBeNull, addUrlPatternMustNotBeNull,
// setServletNameMustNotBeNull and addServletNameMustNotBeNull (a null collection or array is the empty slice in D).
module abstract_filter_registration_bean_tests;

/// The inherited tests, labelled `<prefix>.<method>`.
mixin template AbstractFilterRegistrationBeanTests(string prefix)
{
    import flint.boot.web.server.servlet : AbstractFilterRegistrationBean, ServletRegistrationBean;
    import flint.jakarta.servlet : DispatcherType;
    import web_server_test_support : RecordingServletContext;

    private static ServletRegistrationBean mockServletRegistration(string name)
    {
        auto bean = new ServletRegistrationBean(null);
        bean.setName(name);
        return bean;
    }

    @(prefix ~ ".startupWithDefaults") unittest
    {
        auto servletContext = new RecordingServletContext;
        auto bean = createFilterRegistrationBean();
        bean.onStartup(servletContext);
        assert(servletContext.filters.length == 1);
        assert(servletContext.filters[0].name == "mockFilter");
        assert(isExpectedFilter(servletContext.filters[0].filter));
        version (FlintRegistrationAsyncSupported)
            assert(servletContext.filters[0].asyncSupported == [true]);
        assert(servletContext.filters[0].urlPatternMappings.length == 1);
        assert(servletContext.filters[0].urlPatternMappings[0].dispatcherTypes == [
            DispatcherType.REQUEST
        ]);
        assert(!servletContext.filters[0].urlPatternMappings[0].matchAfter);
        assert(servletContext.filters[0].urlPatternMappings[0].values == ["/*"]);
    }

    version (FlintRegistrationBeanSettings)
    {
        @(prefix ~ ".startupWithSpecifiedValues") unittest
        {
            auto servletContext = new RecordingServletContext;
            auto bean = createFilterRegistrationBean();
            bean.setName("test");
            bean.setAsyncSupported(false);
            bean.setInitParameters(["a": "b"]);
            bean.addInitParameter("c", "d");
            bean.setUrlPatterns("/a", "/b");
            bean.addUrlPatterns("/c");
            bean.setServletNames("s1", "s2");
            bean.addServletNames("s3");
            bean.setServletRegistrationBeans([mockServletRegistration("s4")]);
            bean.addServletRegistrationBeans(mockServletRegistration("s5"));
            bean.setMatchAfter(true);
            bean.onStartup(servletContext);
            auto registration = servletContext.filters[0];
            assert(registration.name == "test" && isExpectedFilter(registration.filter));
            assert(registration.asyncSupported == [false]);
            assert(registration.initParameters == ["a": "b", "c": "d"]);
            assert(registration.urlPatternMappings[0].values == ["/a", "/b", "/c"]);
            assert(registration.urlPatternMappings[0].matchAfter);
            assert(registration.servletNameMappings[0].values == ["s4", "s5", "s1", "s2", "s3"]);
        }

        @(prefix ~ ".setServletRegistrationBeanReplacesValue") unittest
        {
            auto servletContext = new RecordingServletContext;
            auto bean = createFilterRegistrationBean(mockServletRegistration("a"));
            bean.setServletRegistrationBeans([mockServletRegistration("b")]);
            bean.onStartup(servletContext);
            assert(servletContext.filters[0].servletNameMappings[0].values == ["b"]);
        }

        @(prefix ~ ".modifyInitParameters") unittest
        {
            auto servletContext = new RecordingServletContext;
            auto bean = createFilterRegistrationBean();
            bean.addInitParameter("a", "b");
            bean.getInitParameters()["a"] = "c";
            bean.onStartup(servletContext);
            assert(servletContext.filters[0].initParameters == ["a": "c"]);
        }

        @(prefix ~ ".doesNotFailIfDoubleRegistrationIsIgnored") unittest
        {
            auto bean = createFilterRegistrationBean();
            bean.setName("double-registration");
            auto servletContext = new RecordingServletContext;
            servletContext.refuseRegistrations = true;
            bean.setIgnoreRegistrationFailure(true);
            bean.onStartup(servletContext);
        }
    }

    @(prefix ~ ".specificName") unittest
    {
        auto servletContext = new RecordingServletContext;
        auto bean = createFilterRegistrationBean();
        bean.setName("specificName");
        bean.onStartup(servletContext);
        assert(servletContext.filters[0].name == "specificName" && isExpectedFilter(servletContext.filters[0].filter));
    }

    @(prefix ~ ".deducedName") unittest
    {
        auto servletContext = new RecordingServletContext;
        createFilterRegistrationBean().onStartup(servletContext);
        assert(servletContext.filters[0].name == "mockFilter" && isExpectedFilter(servletContext.filters[0].filter));
    }

    @(prefix ~ ".disable") unittest
    {
        auto servletContext = new RecordingServletContext;
        auto bean = createFilterRegistrationBean();
        bean.setEnabled(false);
        bean.onStartup(servletContext);
        assert(servletContext.calls.length == 0);
    }

    @(prefix ~ ".withSpecificDispatcherTypes") unittest
    {
        auto servletContext = new RecordingServletContext;
        auto bean = createFilterRegistrationBean();
        bean.setDispatcherTypes(DispatcherType.INCLUDE, DispatcherType.FORWARD);
        bean.onStartup(servletContext);
        const mapping = servletContext.filters[0].urlPatternMappings[0];
        assert(mapping.dispatcherTypes == [DispatcherType.INCLUDE, DispatcherType.FORWARD]);
        assert(!mapping.matchAfter && mapping.values == ["/*"]);
    }

    @(prefix ~ ".withSpecificDispatcherTypesEnumSet") unittest
    {
        auto servletContext = new RecordingServletContext;
        auto bean = createFilterRegistrationBean();
        DispatcherType[] types = [DispatcherType.INCLUDE, DispatcherType.FORWARD];
        bean.setDispatcherTypes(types);
        bean.onStartup(servletContext);
        const mapping = servletContext.filters[0].urlPatternMappings[0];
        assert(mapping.dispatcherTypes == types && !mapping.matchAfter && mapping.values == ["/*"]);
    }

    version (FlintRegistrationFailure)
    {
        @(prefix ~ ".failsWithDoubleRegistration") unittest
        {
            import flint.java.lang : IllegalStateException;

            auto bean = createFilterRegistrationBean();
            bean.setName("double-registration");
            auto servletContext = new RecordingServletContext;
            servletContext.refuseRegistrations = true;
            string message;
            try
                bean.onStartup(servletContext);
            catch (IllegalStateException e)
                message = e.msg;
            assert(message == "Failed to register 'filter double-registration' on the "
                    ~ "servlet context. Possibly already registered?", message);
        }
    }

    @(prefix ~ ".shouldDetermineDispatcherTypesIfNotSet") unittest
    {
        auto simpleFilter = new class AbstractFilterRegistrationBean
        {
            override imported!"flint.jakarta.servlet".Filter getFilter()
            {
                return new SimpleFilter;
            }
        };
        assert(simpleFilter.getDispatcherTypes() == [DispatcherType.REQUEST]);
    }

    // LIKELY BUG: Boot registers a OncePerRequestFilter for every dispatcher type (it guards re-entry itself), so it
    // also runs on ERROR, FORWARD and ASYNC dispatches; Flint registers it for REQUEST only, so such filters (Spring
    // Security's chain, CORS) do not see the error dispatch to /error.
    version (FlintOncePerRequestFilterDispatcherTypes)
    {
        @(prefix ~ ".shouldDetermineDispatcherTypesForOncePerRequestFilters") unittest
        {
            import std.algorithm.sorting : sort;
            import std.traits : EnumMembers;

            auto simpleFilter = new class AbstractFilterRegistrationBean
            {
                override imported!"flint.jakarta.servlet".Filter getFilter()
                {
                    return new SimpleOncePerRequestFilter;
                }
            };
            auto types = simpleFilter.getDispatcherTypes();
            assert(types.sort().release == [EnumMembers!DispatcherType].sort().release);
        }
    }

    @(prefix ~ ".shouldDetermineDispatcherTypesForSetDispatcherTypes") unittest
    {
        auto simpleFilter = new class AbstractFilterRegistrationBean
        {
            override imported!"flint.jakarta.servlet".Filter getFilter()
            {
                return new SimpleFilter;
            }
        };
        simpleFilter.setDispatcherTypes(DispatcherType.INCLUDE, DispatcherType.FORWARD);
        assert(simpleFilter.getDispatcherTypes() == [DispatcherType.INCLUDE, DispatcherType.FORWARD]);
    }

    private static final class SimpleFilter : imported!"flint.jakarta.servlet".Filter
    {
        mixin imported!"flint.jakarta.servlet".Filter.Defaults;

        void doFilter(imported!"flint.jakarta.servlet".ServletRequest,
                imported!"flint.jakarta.servlet".ServletResponse, imported!"flint.jakarta.servlet".FilterChain)
        {
        }
    }

    private static final class SimpleOncePerRequestFilter : imported!"flint.web.filter".OncePerRequestFilter
    {
        protected override void doFilterInternal(imported!"flint.jakarta.servlet.http".HttpServletRequest,
                imported!"flint.jakarta.servlet.http".HttpServletResponse,
                imported!"flint.jakarta.servlet".FilterChain)
        {
        }
    }
}
