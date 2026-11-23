/// The slice of spring-context's `ConfigurableApplicationContext` that `FlintApplication` drives.
///
/// framework-core owns `flint.context`. Until its `ConfigurableApplicationContext` exists, Boot runs any context
/// through this interface, under the same method names. A context module (framework-core's annotation context,
/// web-mvc's servlet context, a test's stub) provides one through `ApplicationContextFactory`. The day
/// `flint.context` lands, this file is deleted and Boot uses the real type.
module flint.boot.internal.context;

import flint.engine.aot.bean : BeanFactory;

@safe:

/// A refreshable application context.
interface ConfigurableApplicationContext
{
    /// The context's id, used in log lines.
    string getId();

    /// Hand the context the environment Boot prepared (`flint.boot.ApplicationEnvironment`).
    void setEnvironment(Object environment);

    /// Register a ready-made singleton before refresh (`flintApplicationArguments`, `flintBootBanner`).
    void registerSingleton(string name, Object singleton);

    /// Create the beans: generated definitions, conditions, initialization, and start lifecycle beans (the web
    /// server).
    void refresh();

    /// The bean factory, for the runners and failure analyzers.
    BeanFactory getBeanFactory();

    /// Whether the context is refreshed and not yet closed.
    bool isActive();

    /// Stop lifecycle beans, destroy singletons, close.
    void close();

    /// Block until the context is closed by a shutdown signal; returns at once when nothing keeps the process
    /// alive (no web server). Java's non-daemon server threads do this implicitly; a D `main` must wait.
    void awaitTermination();
}
