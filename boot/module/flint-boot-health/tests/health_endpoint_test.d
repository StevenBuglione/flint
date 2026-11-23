// Ported from spring-boot v4.2.0: module/spring-boot-health/src/test/java/org/springframework/boot/health/actuate/endpoint/HealthEndpointTests.java
// with HealthEndpointWebExtensionTests.java, SimpleStatusAggregatorTests.java and SimpleHttpCodeStatusMapperTests.java
// from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the endpoint runs over the auto-configured groups (primary and probes) and a
// registry built in the test; JSON is written by flint.jackson as the web layer writes it.
module health_endpoint_test;

import flint.boot.actuate.endpoint : ApiVersion, SecurityContext;
import flint.boot.availability : ApplicationAvailabilityBean, AvailabilityChangeEvent, LivenessState, ReadinessState;
import flint.boot.health.actuate.endpoint;
import flint.boot.health.application : LivenessStateHealthIndicator, ReadinessStateHealthIndicator;
import flint.boot.health.autoconfigure : AutoConfiguredHealthEndpointGroups,
    HealthEndpointProperties, healthContributorName;
import flint.boot.health.contributor : Health, HealthIndicator, PingHealthIndicator, Status;
import flint.boot.health.registry : DefaultHealthContributorRegistry;
import flint.engine.aot.any : Any;

@safe:

private final class Fixed : HealthIndicator
{
    private Health value;

    this(Health value)
    {
        this.value = value;
    }

    Health health()
    {
        return value;
    }
}

private HealthEndpointWebExtension extension(Health extra = null)
{
    auto availability = new ApplicationAvailabilityBean;
    availability.dispatchEvent(new AvailabilityChangeEvent!LivenessState(availability, LivenessState.CORRECT));
    availability.dispatchEvent(new AvailabilityChangeEvent!ReadinessState(availability,
            ReadinessState.ACCEPTING_TRAFFIC));
    auto registry = new DefaultHealthContributorRegistry;
    registry.registerContributor("ping", new PingHealthIndicator);
    registry.registerContributor("livenessState", new LivenessStateHealthIndicator(availability));
    registry.registerContributor("readinessState", new ReadinessStateHealthIndicator(availability));
    if (extra !is null)
        registry.registerContributor("db", new Fixed(extra));
    return new HealthEndpointWebExtension(registry,
            new AutoConfiguredHealthEndpointGroups(new HealthEndpointProperties, true));
}

private string json(WebEndpointResponseBody body)
{
    import flint.boot.actuate.endpoint.web : Link;
    import flint.engine.aot.descriptor : descriptorOf;
    import flint.jackson.databind : JsonMapper;
    import flint.java.util : LinkedHashMap;

    auto mapper = new JsonMapper;
    mapper.descriptors().add(descriptorOf!SystemHealthDescriptor());
    mapper.descriptors().add(descriptorOf!CompositeHealthDescriptor());
    mapper.descriptors().add(descriptorOf!IndicatedHealthDescriptor());
    mapper.descriptors().add(descriptorOf!(LinkedHashMap!(string, HealthDescriptor))());
    mapper.descriptors().add(descriptorOf!(LinkedHashMap!(string, Any))());
    mapper.descriptors().add(descriptorOf!(string[])());
    return mapper.writeValueAsString(body);
}

private alias WebEndpointResponseBody = Any;

@("health: the system's status and the group names, without components (show-details never)") unittest
{
    auto response = extension().health(ApiVersion.V3, SecurityContext.NONE, false);
    assert(response.getStatus() == 200);
    assert(json(response.getBody()) == `{"groups":["liveness","readiness"],"status":"UP"}`, json(response.getBody()));
}

@("healthForPath: a probe group is its member's status") unittest
{
    auto liveness = extension().health(ApiVersion.V3, SecurityContext.NONE, false, "liveness");
    assert(liveness.getStatus() == 200);
    assert(json(liveness.getBody()) == `{"status":"UP"}`, json(liveness.getBody()));
    auto readiness = extension().health(ApiVersion.V3, SecurityContext.NONE, false, "readiness");
    assert(json(readiness.getBody()) == `{"status":"UP"}`);
}

@("an unknown path is 404; a hidden component path is 404") unittest
{
    assert(extension().health(ApiVersion.V3, SecurityContext.NONE, false, "missing").getStatus() == 404);
    assert(extension().health(ApiVersion.V3, SecurityContext.NONE, false, "ping").getStatus() == 404);
}

@("showAll shows components, sorted by name") unittest
{
    auto response = extension().health(ApiVersion.V3, SecurityContext.NONE, true);
    assert(json(response.getBody()) == `{"components":{"livenessState":{"status":"UP"},"ping":{"status":"UP"},`
            ~ `"readinessState":{"status":"UP"}},"groups":["liveness","readiness"],"status":"UP"}`,
            json(response.getBody()));
}

@("a DOWN contributor makes the system DOWN and 503") unittest
{
    auto response = extension(Health.down().build()).health(ApiVersion.V3, SecurityContext.NONE, false);
    assert(response.getStatus() == 503);
    assert(json(response.getBody()) == `{"groups":["liveness","readiness"],"status":"DOWN"}`);
}

@("SimpleStatusAggregator: the first status in the default order wins; none is UNKNOWN") unittest
{
    auto aggregator = new SimpleStatusAggregator;
    assert(aggregator.getAggregateStatus(Status.UP, Status.DOWN, Status.UNKNOWN).getCode() == "DOWN");
    assert(aggregator.getAggregateStatus(Status.UP, Status.OUT_OF_SERVICE).getCode() == "OUT_OF_SERVICE");
    assert(aggregator.getAggregateStatus().getCode() == "UNKNOWN");
    assert(aggregator.getAggregateStatus(new Status("CUSTOM")).getCode() == "UNKNOWN");
}

@("SimpleHttpCodeStatusMapper: DOWN and OUT_OF_SERVICE are 503") unittest
{
    auto mapper = new SimpleHttpCodeStatusMapper;
    assert(mapper.getStatusCode(Status.DOWN) == 503 && mapper.getStatusCode(Status.OUT_OF_SERVICE) == 503);
    assert(mapper.getStatusCode(Status.UP) == 200 && mapper.getStatusCode(Status.UNKNOWN) == 200);
}

@("HealthContributorNameGenerator: standard suffixes are removed") unittest
{
    assert(healthContributorName("livenessStateHealthIndicator") == "livenessState");
    assert(healthContributorName("pingHealthContributor") == "ping");
    assert(healthContributorName("db") == "db");
}
