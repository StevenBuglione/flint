/// flint:starter-observability: health, readiness and Prometheus metrics on the application's server, and OTLP
/// export when configured (ADR-028 section 6).
///
/// With flint:starter-web, `runApplication!(ObservabilityAutoConfiguration, ...)` serves
/// `<path_prefix>/health/live`, `/health/ready` and `/metrics`. The `Observability` bean exposes the registry for
/// the application's own counters, histograms and health probes.
module flint.starter_observability;

import flint.actuator : Registry;
import flint.arena : Error, Status;
import flint.config : ConfigurationProperties;
import flint.di : AutoConfiguration, PostConstruct, PreDestroy, Provided, Service;
import flint.web : Server, ServerCustomizer;

public import flint.actuator : Counter, Health, HealthProbe, HealthStatus, Histogram;

@safe:

/// The `[management]` section. Every key is optional.
@ConfigurationProperties("management")
struct ManagementProperties
{
    /// Path under which the endpoints are served.
    string pathPrefix = "/actuator";
    /// OTLP resource service name.
    string serviceName = "flint";
    /// OTLP/HTTP base URL; empty records locally only.
    string otlpEndpoint;
    /// Upper bound on metric series.
    uint maxMetricSeries = 4096;
}

/// The actuator registry, opened at start-up, attached to the server, and closed at shutdown.
@Service final class Observability : ServerCustomizer
{
    private ManagementProperties properties;
    private Registry store;

    /// Receive the bound settings.
    this(ManagementProperties properties)
    {
        this.properties = properties;
    }

    /// Open the registry, and the OTLP exporter when an endpoint is configured.
    @PostConstruct Error open()
    {
        import flint.actuator : ActuatorOptions;

        ActuatorOptions options;
        options.pathPrefix = properties.pathPrefix;
        options.serviceName = properties.serviceName;
        options.otlpEndpoint = properties.otlpEndpoint;
        options.maxMetricSeries = properties.maxMetricSeries;
        return store.open(options);
    }

    /// Register the endpoints on the application's server.
    Error customize(ref Server server)
    {
        return store.attach(server);
    }

    /// The registry, for the application's counters, histograms and health probes.
    ref Registry registry() return
    {
        return store;
    }

    /// Report not-ready, and finish a bounded export.
    @PreDestroy void close() nothrow
    {
        import flint.conc : Context;

        Context context;
        cast(void) store.close(context);
    }
}

/// The starter's registrations.
alias ObservabilityAutoConfiguration = AutoConfiguration!(Provided!ManagementProperties, Observability);
