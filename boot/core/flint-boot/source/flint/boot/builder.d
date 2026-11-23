// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/builder/SpringApplicationBuilder.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: "Spring" becomes "Flint"; `Class<?>` sources are `ClassRef`s; context hierarchies
// (`parent`, `child`, `sibling`), `headless` and `environment` are deferred (see docs/spring/phase1/boot.md).

/// `org.springframework.boot.builder`: a fluent builder for `FlintApplication`.
///
/// ```d
/// new FlintApplicationBuilder(ClassRef("com.example.App")).profiles("prod").properties("server.port=0").run(args);
/// ```
module flint.boot.builder;

import flint.boot : ApplicationContextFactory, Banner, ClassRef, FlintApplication, WebApplicationType;
import flint.context : ConfigurableApplicationContext;

@safe:

/// Builds and runs a `FlintApplication`.
final class FlintApplicationBuilder
{
    private FlintApplication application;
    private ClassRef[] sources_;
    private string[] additionalProfiles;
    private string[string] defaultProperties;
    private ConfigurableApplicationContext context;

    /// A builder of an application from `sources`.
    this(ClassRef[] sources...)
    {
        this.sources_ = sources.dup;
        this.application = new FlintApplication(sources);
    }

    /// The application being built (Boot's `application()`; `application` is a member name in D).
    FlintApplication getApplication() pure nothrow @nogc
    {
        return application;
    }

    /// The context, once `run` has returned.
    ConfigurableApplicationContext getContext() pure nothrow @nogc
    {
        return context;
    }

    /// Run the application and keep its context.
    ConfigurableApplicationContext run(string[] args...)
    {
        context = application.run(args.dup);
        return context;
    }

    /// The configured application, without running it.
    FlintApplication build()
    {
        return application;
    }

    /// Add sources.
    FlintApplicationBuilder sources(ClassRef[] sources...)
    {
        this.sources_ ~= sources;
        return this;
    }

    /// The web application type.
    FlintApplicationBuilder web(WebApplicationType webApplicationType)
    {
        application.setWebApplicationType(webApplicationType);
        return this;
    }

    /// Whether to log startup information.
    FlintApplicationBuilder logStartupInfo(bool logStartupInfo)
    {
        application.setLogStartupInfo(logStartupInfo);
        return this;
    }

    /// The banner.
    FlintApplicationBuilder banner(Banner banner)
    {
        application.setBanner(banner);
        return this;
    }

    /// The banner mode.
    FlintApplicationBuilder bannerMode(Banner.Mode bannerMode)
    {
        application.setBannerMode(bannerMode);
        return this;
    }

    /// The main application class.
    FlintApplicationBuilder main(ClassRef mainApplicationClass)
    {
        application.setMainApplicationClass(mainApplicationClass);
        return this;
    }

    /// Default properties as `key=value` or `key:value` pairs; a key alone has an empty value.
    FlintApplicationBuilder properties(string[] defaultProperties...)
    {
        string[string] map;
        foreach (property; defaultProperties)
        {
            const index = lowestIndexOf(property);
            map[index > 0 ? property[0 .. index] : property] = index > 0 ? property[index + 1 .. $] : "";
        }
        return properties(map);
    }

    /// Default properties from a map; later calls add to earlier ones.
    FlintApplicationBuilder properties(string[string] defaults)
    {
        foreach (key, value; defaults)
            defaultProperties[key] = value;
        application.setDefaultProperties(defaultProperties);
        return this;
    }

    /// Additional active profiles; later calls add to earlier ones.
    FlintApplicationBuilder profiles(string[] profiles...)
    {
        foreach (profile; profiles)
            additionalProfiles ~= profile;
        application.setAdditionalProfiles(additionalProfiles);
        return this;
    }

    /// The context factory.
    FlintApplicationBuilder contextFactory(ApplicationContextFactory factory)
    {
        application.setApplicationContextFactory(factory);
        return this;
    }

    private static long lowestIndexOf(string property) pure nothrow @nogc
    {
        foreach (index, char ch; property)
        {
            if (ch == ':' || ch == '=')
                return cast(long) index;
        }
        return -1;
    }
}
