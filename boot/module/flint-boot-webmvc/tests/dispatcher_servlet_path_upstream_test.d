// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/DispatcherServletPathTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the test methods error_test.d does not port (its "DispatcherServletPath
// .getServletUrlMapping" test holds the empty, slash, and with or without trailing slash cases, through
// `DispatcherServletRegistrationBean`, which implements `DispatcherServletPath` in Boot). Flint has no
// `DispatcherServletPath` interface yet; those cases wait behind FlintDispatcherServletPath.
module dispatcher_servlet_path_upstream_test;

@safe:

// Boot's DispatcherServletPath (a functional interface over the path) with getRelativePath, getPrefix and
// getServletUrlMapping; Flint keeps only a private copy of the mapping in DispatcherServletRegistrationBean, which
// appends "/*" to a path holding a wildcard where Boot returns the path unchanged.
version (FlintDispatcherServletPath)
{
    import flint.boot.webmvc.autoconfigure : DispatcherServletPath;

    private DispatcherServletPath path(string value)
    {
        return () => value;
    }

    @("DispatcherServletPathTests.getRelativePathReturnsRelativePath") unittest
    {
        assert(path("spring").getRelativePath("boot") == "spring/boot");
        assert(path("spring/").getRelativePath("boot") == "spring/boot");
        assert(path("spring").getRelativePath("/boot") == "spring/boot");
    }

    @("DispatcherServletPathTests.getPrefixWhenHasSimplePathReturnPath") unittest
    {
        assert(path("spring").getPrefix() == "spring");
    }

    @("DispatcherServletPathTests.getPrefixWhenHasPatternRemovesPattern") unittest
    {
        assert(path("spring/*.do").getPrefix() == "spring");
    }

    @("DispatcherServletPathTests.getPathWhenPathEndsWithSlashRemovesSlash") unittest
    {
        assert(path("spring/").getPrefix() == "spring");
    }

    @("DispatcherServletPathTests.getServletUrlMappingWhenPathContainsStarReturnsPath") unittest
    {
        import flint.boot.webmvc.autoconfigure : DispatcherServletRegistrationBean;
        import flint.web.servlet : DispatcherServlet, DispatcherStrategies;

        assert(path("spring/*.do").getServletUrlMapping() == "spring/*.do");
        assert(new DispatcherServletRegistrationBean(new DispatcherServlet(DispatcherStrategies.init),
                "spring/*.do").getUrlMappings() == ["spring/*.do"]);
    }
}
