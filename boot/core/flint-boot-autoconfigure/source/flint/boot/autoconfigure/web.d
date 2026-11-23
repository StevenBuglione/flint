// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/web/ErrorProperties.java
// with WebProperties.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java Beans getters and setters are kept (rulebook R6); `@Value("${error.path:/error}")`
// on `path` is resolved by the server properties that nest this class.

/// `org.springframework.boot.autoconfigure.web`: web properties shared by the server modules.
module flint.boot.autoconfigure.web;

import flint.boot.context.properties : ConfigurationProperties;

@safe:

/// Error handling settings, bound under `flint.web.error` through `WebProperties` (Boot 4 deprecated `flint.web.error.*` at
/// error level in favour of `spring.web.error.*`).
final class ErrorProperties
{
    /// When an attribute is included.
    enum IncludeAttribute
    {
        /// Never.
        NEVER,
        /// Always.
        ALWAYS,
        /// When the request has the matching parameter (`?trace`, `?message`, `?errors`, `?path`) not `false`.
        ON_PARAM
    }

    /// `flint.web.error.whitelabel.*`.
    static final class Whitelabel
    {
        private bool enabled = true;

        /// Whether the default HTML error page is shown (`flint.web.error.whitelabel.enabled`, default true).
        bool isEnabled() const pure nothrow @nogc
        {
            return enabled;
        }

        /// Set `enabled`.
        void setEnabled(bool enabled) pure nothrow @nogc
        {
            this.enabled = enabled;
        }
    }

    private string path = "/error";
    private bool includeException;
    private IncludeAttribute includeStacktrace = IncludeAttribute.NEVER;
    private IncludeAttribute includeMessage = IncludeAttribute.NEVER;
    private IncludeAttribute includeBindingErrors = IncludeAttribute.NEVER;
    private IncludeAttribute includePath = IncludeAttribute.ALWAYS;
    private Whitelabel whitelabel;

    /// Defaults as Boot's.
    this() pure nothrow
    {
        whitelabel = new Whitelabel;
    }

    /// The error controller's path (`flint.web.error.path`, default `/error`).
    string getPath() const pure nothrow @nogc
    {
        return path;
    }

    /// Set `path`.
    void setPath(string path) pure nothrow @nogc
    {
        this.path = path;
    }

    /// Whether the `exception` attribute is included (`flint.web.error.include-exception`, default false).
    bool isIncludeException() const pure nothrow @nogc
    {
        return includeException;
    }

    /// Set `includeException`.
    void setIncludeException(bool includeException) pure nothrow @nogc
    {
        this.includeException = includeException;
    }

    /// When the `trace` attribute is included (`flint.web.error.include-stacktrace`, default `NEVER`).
    IncludeAttribute getIncludeStacktrace() const pure nothrow @nogc
    {
        return includeStacktrace;
    }

    /// Set `includeStacktrace`.
    void setIncludeStacktrace(IncludeAttribute value) pure nothrow @nogc
    {
        includeStacktrace = value;
    }

    /// When the `message` attribute is included (`flint.web.error.include-message`, default `NEVER`).
    IncludeAttribute getIncludeMessage() const pure nothrow @nogc
    {
        return includeMessage;
    }

    /// Set `includeMessage`.
    void setIncludeMessage(IncludeAttribute value) pure nothrow @nogc
    {
        includeMessage = value;
    }

    /// When the `errors` attribute is included (`flint.web.error.include-binding-errors`, default `NEVER`).
    IncludeAttribute getIncludeBindingErrors() const pure nothrow @nogc
    {
        return includeBindingErrors;
    }

    /// Set `includeBindingErrors`.
    void setIncludeBindingErrors(IncludeAttribute value) pure nothrow @nogc
    {
        includeBindingErrors = value;
    }

    /// When the `path` attribute is included (`flint.web.error.include-path`, default `ALWAYS`).
    IncludeAttribute getIncludePath() const pure nothrow @nogc
    {
        return includePath;
    }

    /// Set `includePath`.
    void setIncludePath(IncludeAttribute value) pure nothrow @nogc
    {
        includePath = value;
    }

    /// `flint.web.error.whitelabel.*`.
    Whitelabel getWhitelabel() pure nothrow @nogc
    {
        return whitelabel;
    }
}

/// General web settings. Bound under `flint.web` (Boot's `spring.web` is accepted as an alias).
@ConfigurationProperties("flint.web")
final class WebProperties
{
    /// How the locale is resolved.
    enum LocaleResolver
    {
        /// Always use the configured locale.
        FIXED,
        /// Use the "Accept-Language" header, or the configured locale if the header is not set.
        ACCEPT_HEADER
    }

    /// Static resource handling.
    static final class Resources
    {
        private string[] staticLocations = [
            "classpath:/META-INF/resources/", "classpath:/resources/", "classpath:/static/",
            "classpath:/public/"
        ];
        private bool addMappings = true;

        /// Locations of static resources.
        string[] getStaticLocations() pure nothrow @nogc
        {
            return staticLocations;
        }

        /// Set `staticLocations`.
        void setStaticLocations(string[] staticLocations) pure nothrow @nogc
        {
            this.staticLocations = staticLocations;
        }

        /// Whether to enable default resource handling.
        bool isAddMappings() const pure nothrow @nogc
        {
            return addMappings;
        }

        /// Set `addMappings`.
        void setAddMappings(bool addMappings) pure nothrow @nogc
        {
            this.addMappings = addMappings;
        }
    }

    private string locale;
    private LocaleResolver localeResolver = LocaleResolver.ACCEPT_HEADER;
    private Resources resources;
    private ErrorProperties error;

    /// Boot's defaults.
    this() pure nothrow
    {
        resources = new Resources;
        error = new ErrorProperties;
    }

    /// Locale to use (a language tag such as `en-US`). By default, this locale is overridden by the "Accept-Language"
    /// header.
    string getLocale() const pure nothrow @nogc
    {
        return locale;
    }

    /// Set `locale`.
    void setLocale(string locale) pure nothrow @nogc
    {
        this.locale = locale;
    }

    /// Define how the locale should be resolved.
    LocaleResolver getLocaleResolver() const pure nothrow @nogc
    {
        return localeResolver;
    }

    /// Set `localeResolver`.
    void setLocaleResolver(LocaleResolver localeResolver) pure nothrow @nogc
    {
        this.localeResolver = localeResolver;
    }

    /// Static resource handling (`flint.web.resources.*`).
    Resources getResources() pure nothrow @nogc
    {
        return resources;
    }

    /// Error handling (`flint.web.error.*`).
    ErrorProperties getError() pure nothrow @nogc
    {
        return error;
    }
}
