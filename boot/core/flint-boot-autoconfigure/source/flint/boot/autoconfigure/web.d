// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/web/ErrorProperties.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java Beans getters and setters are kept (rulebook R6); `@Value("${error.path:/error}")`
// on `path` is resolved by the server properties that nest this class.

/// `org.springframework.boot.autoconfigure.web`: web properties shared by the server modules.
module flint.boot.autoconfigure.web;

@safe:

/// Error handling settings, bound under `server.error`.
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

    /// `server.error.whitelabel.*`.
    static final class Whitelabel
    {
        private bool enabled = true;

        /// Whether the default HTML error page is shown (`server.error.whitelabel.enabled`, default true).
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

    /// The error controller's path (`server.error.path`, default `/error`).
    string getPath() const pure nothrow @nogc
    {
        return path;
    }

    /// Set `path`.
    void setPath(string path) pure nothrow @nogc
    {
        this.path = path;
    }

    /// Whether the `exception` attribute is included (`server.error.include-exception`, default false).
    bool isIncludeException() const pure nothrow @nogc
    {
        return includeException;
    }

    /// Set `includeException`.
    void setIncludeException(bool includeException) pure nothrow @nogc
    {
        this.includeException = includeException;
    }

    /// When the `trace` attribute is included (`server.error.include-stacktrace`, default `NEVER`).
    IncludeAttribute getIncludeStacktrace() const pure nothrow @nogc
    {
        return includeStacktrace;
    }

    /// Set `includeStacktrace`.
    void setIncludeStacktrace(IncludeAttribute value) pure nothrow @nogc
    {
        includeStacktrace = value;
    }

    /// When the `message` attribute is included (`server.error.include-message`, default `NEVER`).
    IncludeAttribute getIncludeMessage() const pure nothrow @nogc
    {
        return includeMessage;
    }

    /// Set `includeMessage`.
    void setIncludeMessage(IncludeAttribute value) pure nothrow @nogc
    {
        includeMessage = value;
    }

    /// When the `errors` attribute is included (`server.error.include-binding-errors`, default `NEVER`).
    IncludeAttribute getIncludeBindingErrors() const pure nothrow @nogc
    {
        return includeBindingErrors;
    }

    /// Set `includeBindingErrors`.
    void setIncludeBindingErrors(IncludeAttribute value) pure nothrow @nogc
    {
        includeBindingErrors = value;
    }

    /// When the `path` attribute is included (`server.error.include-path`, default `ALWAYS`).
    IncludeAttribute getIncludePath() const pure nothrow @nogc
    {
        return includePath;
    }

    /// Set `includePath`.
    void setIncludePath(IncludeAttribute value) pure nothrow @nogc
    {
        includePath = value;
    }

    /// `server.error.whitelabel.*`.
    Whitelabel getWhitelabel() pure nothrow @nogc
    {
        return whitelabel;
    }
}
