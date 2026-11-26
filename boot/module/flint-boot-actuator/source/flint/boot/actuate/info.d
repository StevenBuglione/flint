// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/main/java/org/springframework/boot/actuate/info/Info.java
// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/main/java/org/springframework/boot/actuate/info/InfoContributor.java
// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/main/java/org/springframework/boot/actuate/info/InfoEndpoint.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors.
module flint.boot.actuate.info;

import flint.boot.actuate.endpoint.annotation : Endpoint, ReadOperation;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, JavaObject;
import flint.java.util : Collections, LinkedHashMap, List, Map;

@safe:

/// An immutable snapshot of application information.
final class Info
{
    private Map!(string, Any) details;

    private this(Map!(string, Any) details)
    {
        this.details = Collections.unmodifiableMap(details);
    }

    /// The application information in insertion order.
    Map!(string, Any) getDetails()
    {
        return details;
    }

    /// A named detail, or an empty Any if it is absent.
    Any get(string id)
    {
        return details.get(id);
    }

    /// Compare the contents of two snapshots.
    bool equals(Object other)
    {
        auto info = cast(Info) other;
        return this is info || (info !is null && details.equals(cast(Object) info.details));
    }

    /// Hash the snapshot content.
    int hashCode()
    {
        return details.hashCode();
    }

    /// Render the detail map as text.
    override string toString()
    {
        return details.toString();
    }

    mixin JavaObject;

    /// Collect the details supplied by contributors.
    static final class Builder
    {
        private LinkedHashMap!(string, Any) content;

        /// Start with no details.
        this()
        {
            content = new LinkedHashMap!(string, Any);
        }

        /// Add or replace one detail.
        Builder withDetail(string key, Any value)
        {
            content.put(key, value);
            return this;
        }

        /// Box a value as a Java Object (R11).
        Builder withDetail(T)(string key, T value)
        {
            return withDetail(key, Any.of(value));
        }

        /// Add all entries from a set of details.
        Builder withDetails(Map!(string, Any) details)
        {
            content.putAll(details);
            return this;
        }

        /// Freeze a copy of this builder's current details.
        Info build()
        {
            return new Info(content);
        }
    }
}

/// Contribute a portion of the application's detail map.
interface InfoContributor
{
    /// Add this contributor's information to the supplied builder.
    void contribute(Info.Builder builder);
}

private alias Contribution = void delegate(Info.Builder) @safe;

@Endpoint("info")
 /// The Actuator operation that supplies application information.
class InfoEndpoint
{
    private List!InfoContributor contributors;
    private Contribution[] actions;

    /// Use an ordered list of contributors.
    this(List!InfoContributor contributors)
    {
        if (contributors is null)
            throw new IllegalArgumentException("'infoContributors' must not be null");
        this.contributors = contributors;
    }

    /// Accept D delegates for contributors (R9).
    this(scope Contribution[] actions)
    {
        this.actions = actions.dup;
    }

    @ReadOperation /// Collect the contributors' details.
    Map!(string, Any) info()
    {
        auto builder = new Info.Builder;
        if (contributors !is null)
        {
            foreach (contributor; contributors)
                contributor.contribute(builder);
        }
        foreach (action; actions)
            action(builder);
        return builder.build().getDetails();
    }
}
