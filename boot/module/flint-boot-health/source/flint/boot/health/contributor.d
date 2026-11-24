// Ported from spring-boot v4.2.0: module/spring-boot-health/src/main/java/org/springframework/boot/health/contributor/Status.java
// with Health.java, HealthContributor.java, HealthIndicator.java, CompositeHealthContributor.java,
// AbstractHealthIndicator.java, PingHealthIndicator.java and MapCompositeHealthContributor.java from the same
// directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: details are `LinkedHashMap!(string, Any)` (R12); the sealed `HealthContributor`
// hierarchy is an interface with two sub-interfaces; a composite lists its children as `NamedContributor`s.

/// `org.springframework.boot.health.contributor`: health contributors and the health they report.
module flint.boot.health.contributor;

import flint.engine.aot.any : Any;
import flint.java.util : LinkedHashMap, Map;

@safe:

/// A health status: a code (`UP`, `DOWN`, `OUT_OF_SERVICE`, `UNKNOWN` or custom) and a description.
final class Status
{
    private string code;
    private string description;

    /// The status is not known.
    static Status UNKNOWN()
    {
        return new Status("UNKNOWN");
    }

    /// The component is functioning as expected.
    static Status UP()
    {
        return new Status("UP");
    }

    /// The component has suffered an unexpected failure.
    static Status DOWN()
    {
        return new Status("DOWN");
    }

    /// The component has been taken out of service and should not be used.
    static Status OUT_OF_SERVICE()
    {
        return new Status("OUT_OF_SERVICE");
    }

    /// `DOWN`, `OUT_OF_SERVICE`, `UP`, `UNKNOWN`: the default aggregation order.
    static string[] DEFAULT_ORDER() pure nothrow
    {
        return ["DOWN", "OUT_OF_SERVICE", "UP", "UNKNOWN"];
    }

    /// `code` with an empty description.
    this(string code)
    {
        this(code, "");
    }

    /// `code` with `description`.
    this(string code, string description)
    {
        import flint.java.lang : IllegalArgumentException;

        if (code is null)
            throw new IllegalArgumentException("'code' must not be null");
        this.code = code;
        this.description = description is null ? "" : description;
    }

    /// The code, written as `status`.
    string getCode() const pure nothrow @nogc
    {
        return code;
    }

    /// The description, written when not empty.
    string getDescription() const pure nothrow @nogc
    {
        return description;
    }

    /// Statuses are equal when their codes are.
    override bool opEquals(Object other) const
    {
        auto status = cast(const Status) other;
        return status !is null && status.code == code;
    }

    /// Consistent with `opEquals`.
    override size_t toHash() const nothrow @safe
    {
        return hashOf(code);
    }

    /// The code.
    override string toString() const pure nothrow @nogc
    {
        return code;
    }
}

/// The health of a component: a status and details.
final class Health
{
    private Status status_;
    private LinkedHashMap!(string, Any) details;

    private this(Builder builder)
    {
        this.status_ = builder.status_;
        this.details = builder.details;
    }

    private this(Status status, LinkedHashMap!(string, Any) details) pure nothrow @nogc
    {
        this.status_ = status;
        this.details = details;
    }

    /// The status.
    Status getStatus() pure nothrow @nogc
    {
        return status_;
    }

    /// The details.
    LinkedHashMap!(string, Any) getDetails() pure nothrow @nogc
    {
        return details;
    }

    /// This health without its details.
    Health withoutDetails()
    {
        return details.isEmpty() ? this : new Health(status_, new LinkedHashMap!(string, Any));
    }

    /// A builder with `UNKNOWN`.
    static Builder unknown()
    {
        return status(Status.UNKNOWN);
    }

    /// A builder with `UP`.
    static Builder up()
    {
        return status(Status.UP);
    }

    /// A builder with `DOWN` and `ex` as the `error` detail.
    static Builder down(Throwable ex)
    {
        return down().withException(ex);
    }

    /// A builder with `DOWN`.
    static Builder down()
    {
        return status(Status.DOWN);
    }

    /// A builder with `OUT_OF_SERVICE`.
    static Builder outOfService()
    {
        return status(Status.OUT_OF_SERVICE);
    }

    /// A builder with the status `statusCode`.
    static Builder status(string statusCode)
    {
        return status(new Status(statusCode));
    }

    /// A builder with `status`.
    static Builder status(Status status)
    {
        return new Builder(status);
    }

    /// Builds a `Health`.
    static class Builder
    {
        private Status status_;
        private LinkedHashMap!(string, Any) details;

        /// `UNKNOWN`, no details.
        this()
        {
            this(Status.UNKNOWN);
        }

        /// `status`, no details.
        this(Status status)
        {
            this.status_ = status;
            details = new LinkedHashMap!(string, Any);
        }

        /// Record `exception` as the `error` detail.
        Builder withException(Throwable exception)
        {
            return withDetail("error", Any.of(typeid(exception).name ~ ": " ~ exception.msg.idup));
        }

        /// Add a detail.
        Builder withDetail(string key, Any value)
        {
            details.put(key, value);
            return this;
        }

        /// Set the status to `UNKNOWN`.
        Builder unknown()
        {
            return status(Status.UNKNOWN);
        }

        /// Set the status to `UP`.
        Builder up()
        {
            return status(Status.UP);
        }

        /// Set the status to `DOWN`.
        Builder down()
        {
            return status(Status.DOWN);
        }

        /// Set the status to `DOWN`, with `ex` as the `error` detail.
        Builder down(Throwable ex)
        {
            return down().withException(ex);
        }

        /// Set the status to `OUT_OF_SERVICE`.
        Builder outOfService()
        {
            return status(Status.OUT_OF_SERVICE);
        }

        /// Set the status.
        Builder status(Status status)
        {
            this.status_ = status;
            return this;
        }

        /// The health.
        Health build()
        {
            return new Health(this);
        }
    }
}

/// Contributes to the application's health: a `HealthIndicator` or a `CompositeHealthContributor`.
interface HealthContributor
{
}

/// Reports a component's health.
interface HealthIndicator : HealthContributor
{
    /// The health, with or without its details.
    final Health health(bool includeDetails)
    {
        auto health = health();
        if (health is null)
            return null;
        return includeDetails ? health : health.withoutDetails();
    }

    /// The health.
    Health health();
}

/// A named child of a composite contributor.
struct NamedContributor
{
    /// The child's name.
    string name;
    /// The child.
    HealthContributor contributor;
}

/// A contributor made of named child contributors.
interface CompositeHealthContributor : HealthContributor
{
    /// The child named `name`, or `null`.
    HealthContributor getContributor(string name);

    /// The children, in order.
    NamedContributor[] getContributors();

    /// A composite of `map`'s values, each adapted by `valueAdapter` and named by its key, in the map's order.
    static CompositeHealthContributor fromMap(V)(Map!(string, V) map,
            scope HealthContributor delegate(V) @safe valueAdapter)
    {
        import flint.java.lang : IllegalArgumentException;

        if (map is null)
            throw new IllegalArgumentException("'map' must not be null");
        NamedContributor[] children;
        foreach (name; map.keySet().toArray())
        {
            auto contributor = valueAdapter(map.get(name));
            if (contributor is null)
                throw new IllegalArgumentException("'valueAdapter' must not return null");
            children ~= NamedContributor(name, contributor);
        }
        return new MapCompositeHealthContributor(children);
    }
}

/// `CompositeHealthContributor.fromMap`'s composite: named children in order.
private final class MapCompositeHealthContributor : CompositeHealthContributor
{
    private NamedContributor[] children;

    this(NamedContributor[] children) pure nothrow @nogc
    {
        this.children = children;
    }

    HealthContributor getContributor(string name)
    {
        foreach (child; children)
            if (child.name == name)
                return child.contributor;
        return null;
    }

    NamedContributor[] getContributors()
    {
        return children;
    }
}

/// A `HealthIndicator` whose `doHealthCheck` fills a builder; a check that throws reports `DOWN` with the error.
abstract class AbstractHealthIndicator : HealthIndicator
{
    // The message Java logs, at WARN, when a check throws; Flint's health module does not log yet.
    private string healthCheckFailedMessage = "Health check failed";

    /// With the default failure message.
    protected this() pure nothrow @nogc
    {
    }

    /// With the message that describes a failed health check.
    protected this(string healthCheckFailedMessage) pure nothrow @nogc
    {
        this.healthCheckFailedMessage = healthCheckFailedMessage;
    }

    /// The health from `doHealthCheck`.
    final Health health()
    {
        auto builder = new Health.Builder;
        try
            doHealthCheck(builder);
        catch (Exception ex)
            builder.down(ex);
        return builder.build();
    }

    /// Fill `builder`.
    protected abstract void doHealthCheck(Health.Builder builder);
}

/// Always `UP`: the application is answering.
class PingHealthIndicator : AbstractHealthIndicator
{
    protected override void doHealthCheck(Health.Builder builder)
    {
        builder.up();
    }
}
