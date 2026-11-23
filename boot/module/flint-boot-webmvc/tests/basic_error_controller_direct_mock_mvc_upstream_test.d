// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/error/BasicErrorControllerDirectMockMvcTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the upstream test methods, which error_test.d (whose header names this class) checks
// through the controller's methods; here `SpringApplication.run` with `@MinimalWebConfiguration` becomes
// webmvc_test_support's `MvcFixture` and `MockMvcTester` its `perform`. Not ported: errorControllerWithAop (an
// AspectJ `@Around` advice on `@Controller` beans needs Flint AOT's generated proxies, which a unit test does not
// have).
module basic_error_controller_direct_mock_mvc_upstream_test;

import flint.engine.aot.registry : AotRegistry;
import std.algorithm.searching : canFind;
import webmvc_test_support : mvcFixture;

@safe:

// No application controllers: `@MinimalWebConfiguration` alone.
private void noControllers(scope AotRegistry registry)
{
    import flint.engine.aot.registry : aotContractVersion;

    registry.begin(aotContractVersion, 0);
    registry.end();
}

// SpringApplicationBuilder's parent and child contexts; Flint Boot runs one application context.
version (FlintApplicationContextHierarchy)
{
    @("BasicErrorControllerDirectMockMvcTests.errorPageAvailableWithParentContext") unittest
    {
        import flint.boot.builder : FlintApplicationBuilder;

        const context = new FlintApplicationBuilder!ParentConfiguration().child!ChildConfiguration()
            .run("--server.port=0");
        assert(context !is null);
        auto response = mvcFixture(&noControllers).perform("GET", "/error", null, "text/html");
        assert(response.getStatus() >= 500 && response.getContentAsString().canFind("status=999"));
    }
}

@("BasicErrorControllerDirectMockMvcTests.errorPageAvailableWithMvcIncluded") unittest
{
    auto response = mvcFixture(&noControllers).perform("GET", "/error", null, "text/html");
    assert(response.getStatus() >= 500 && response.getStatus() < 600);
    assert(response.getContentAsString().canFind("status=999"), response.getContentAsString());
}

@("BasicErrorControllerDirectMockMvcTests.errorPageNotAvailableWithWhitelabelDisabled") unittest
{
    import flint.jakarta.servlet : ServletException, ServletRequest, ServletResponse;
    import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
    import std.exception : assertThrown;

    auto fixture = mvcFixture(&noControllers, [["flint.web.error.whitelabel.enabled", "false"]]);
    auto request = new MockHttpServletRequest("GET", "/error");
    request.addHeader("Accept", "text/html");
    assertThrown!ServletException(fixture.servlet.service(cast(ServletRequest) request,
            cast(ServletResponse) new MockHttpServletResponse));
}
