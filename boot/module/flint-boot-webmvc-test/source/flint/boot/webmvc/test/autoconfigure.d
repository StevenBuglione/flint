// Ported from spring-boot v4.2.0: module/spring-boot-webmvc-test/src/main/java/org/springframework/boot/webmvc/test/autoconfigure/WebMvcTest.java
// with AutoConfigureMockMvc.java and MockMvcPrint.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: annotations are UDA structs (rulebook R2); `Class<?>` attributes are `ClassRef`s.

/// `org.springframework.boot.webmvc.test.autoconfigure`: the MVC test slice and MockMvc auto-configuration.
///
/// Annotation module: a leaf of UDA structs. `@WebMvcTest` limits the context to MVC components (controllers,
/// `@ControllerAdvice`, converters, filters) and auto-configures MockMvc; `@AutoConfigureMockMvc` adds a `MockMvc`
/// bean to a full `@FlintBootTest` context. `@AutoConfigureMockMvc`'s attributes map to
/// `flint.test.mockmvc.*` properties, as Boot's `@PropertyMapping("spring.test.mockmvc")` does.
module flint.boot.webmvc.test.autoconfigure;

import flint.boot.autoconfigure : ImportAutoConfiguration;
import flint.boot.context.properties : ClassRef;

@safe:

/// What MockMvc prints for each request.
enum MockMvcPrint
{
    /// The default: `SYSTEM_OUT`, unless `printOnlyOnFailure` holds back successful requests.
    DEFAULT,
    /// Print through the log.
    LOG,
    /// Print to standard output.
    SYSTEM_OUT,
    /// Print to standard error.
    SYSTEM_ERR,
    /// Print nothing.
    NONE
}

/// Auto-configures a `MockMvc` bean in the test's context (`flint.test.mockmvc.*`).
@ImportAutoConfiguration struct AutoConfigureMockMvc
{
    /// HtmlUnit settings (`flint.test.mockmvc.htmlunit.*`).
    struct HtmlUnit
    {
        /// The URL HtmlUnit requests are made against.
        string url = "http://localhost";
        /// Whether a `WebClient` bean is configured (`webclient.enabled`).
        bool webClient = true;
        /// Whether a `WebDriver` bean is configured (`webdriver.enabled`).
        bool webDriver = true;
    }

    /// Whether the context's filters are added to MockMvc (`add-filters`).
    bool addFilters = true;
    /// Where results are printed (`print`), mapped only when not `DEFAULT`.
    MockMvcPrint print = MockMvcPrint.DEFAULT;
    /// Whether only failed requests are printed (`print-only-on-failure`).
    bool printOnlyOnFailure = true;
    /// HtmlUnit settings.
    HtmlUnit htmlUnit;
}

/// A test of the MVC layer only: controllers, advice and converters, with MockMvc auto-configured.
@AutoConfigureMockMvc @ImportAutoConfiguration struct WebMvcTest
{
    /// Properties in `key=value` form.
    string[] properties;
    /// The controllers to test; an alias of `controllers`. All controllers when empty.
    ClassRef[] value;
    /// The controllers to test.
    ClassRef[] controllers;
    /// Whether the default MVC component filters apply.
    bool useDefaultFilters = true;
    /// Auto-configurations to leave out; an alias of `ImportAutoConfiguration.exclude`.
    ClassRef[] excludeAutoConfiguration;
}
