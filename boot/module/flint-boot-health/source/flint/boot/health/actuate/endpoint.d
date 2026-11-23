// Ported from spring-boot v4.2.0: module/spring-boot-health/src/main/java/org/springframework/boot/health/actuate/endpoint/HealthEndpoint.java
// with HealthEndpointSupport.java, HealthEndpointWebExtension.java, HealthDescriptor.java,
// IndicatedHealthDescriptor.java, CompositeHealthDescriptor.java, SystemHealthDescriptor.java, HealthEndpointGroup.java,
// HealthEndpointGroups.java, StatusAggregator.java, SimpleStatusAggregator.java, HttpCodeStatusMapper.java and
// SimpleHttpCodeStatusMapper.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: only the blocking (servlet) side; descriptors write `status` (and a non-empty
// `description`) through their own getters, where Boot unwraps `Status` with `@JsonUnwrapped`, which flint.jackson
// does not apply yet; component maps are `LinkedHashMap`s sorted by name (Boot's `TreeMap`), group names a sorted
// `string[]`; additional health paths (`WebServerNamespace`) and the slow-contributor log follow with the management
// server.

/// `org.springframework.boot.health.actuate.endpoint`: the health endpoint.
module flint.boot.health.actuate.endpoint;

import flint.boot.actuate.endpoint : ApiVersion, EndpointId, OperationResponseBody, SecurityContext;
import flint.boot.actuate.endpoint.web : WebEndpointResponse;
import flint.boot.health.contributor : CompositeHealthContributor, Health, HealthContributor, HealthIndicator, Status;
import flint.boot.health.registry : HealthContributorRegistry;
import flint.engine.aot.any : Any;
import flint.jackson.annotation : JsonIgnore, JsonInclude, JsonProperty;
import flint.java.util : LinkedHashMap;

// `@JsonInclude(Include.NON_EMPTY)`.
private enum JsonInclude nonEmpty = JsonInclude(JsonInclude.Include.NON_EMPTY);

// The JSON view of a component map: each value as its runtime class.
private alias JsonMap = LinkedHashMap!(string, Any);

@safe:

/// Aggregates the statuses of several contributors into one.
interface StatusAggregator
{
    /// The aggregate of `statuses`.
    Status getAggregateStatus(Status[] statuses...);
}

/// Aggregates by an order of status codes: the first in the order wins; unknown codes are ignored.
class SimpleStatusAggregator : StatusAggregator
{
    private string[] order;

    /// With Boot's default order: `DOWN`, `OUT_OF_SERVICE`, `UP`, `UNKNOWN`.
    this()
    {
        this(Status.DEFAULT_ORDER());
    }

    /// With `order`, codes normalised to upper case with underscores.
    this(string[] order...)
    {
        foreach (code; order)
            this.order ~= normalize(code);
    }

    /// The status earliest in the order, else `UNKNOWN`.
    Status getAggregateStatus(Status[] statuses...)
    {
        Status best;
        size_t bestIndex = size_t.max;
        foreach (status; statuses)
        {
            foreach (index, code; order)
            {
                if (code == status.getCode() && index < bestIndex)
                {
                    best = status;
                    bestIndex = index;
                }
            }
        }
        return best is null ? Status.UNKNOWN : best;
    }

    // Boot's getUniformCode: letters and digits upper-cased, other characters become underscores.
    private static string normalize(string code) pure
    {
        import std.ascii : isAlphaNum, toUpper;

        string result;
        foreach (c; code)
            result ~= isAlphaNum(c) ? toUpper(c) : '_';
        return result;
    }
}

/// Maps a status to an HTTP status code.
interface HttpCodeStatusMapper
{
    /// The HTTP status of `status`.
    int getStatusCode(Status status);
}

/// Maps by code, with Boot's defaults: `DOWN` and `OUT_OF_SERVICE` are 503, anything else 200.
class SimpleHttpCodeStatusMapper : HttpCodeStatusMapper
{
    private int[string] mappings;

    /// With Boot's defaults.
    this()
    {
        mappings = [
            "DOWN": WebEndpointResponse.STATUS_SERVICE_UNAVAILABLE,
            "OUT_OF_SERVICE": WebEndpointResponse.STATUS_SERVICE_UNAVAILABLE
        ];
    }

    /// With `mappings` (codes as keys).
    this(int[string] mappings)
    {
        this.mappings = mappings.dup;
    }

    /// The mapped code, else 200.
    int getStatusCode(Status status)
    {
        if (auto code = status.getCode() in mappings)
            return *code;
        return WebEndpointResponse.STATUS_OK;
    }
}

/// What the health endpoint writes for a contributor. Each descriptor declares the getters Jackson writes, since
/// Flint's descriptors list a class's own members. `getStatus` is renamed as well as ignored: flint.jackson drops an
/// ignored name together with any property renamed to it (`getStatusCode` is `status`).
abstract class HealthDescriptor : OperationResponseBody
{
    /// The status.
    @JsonIgnore @JsonProperty("statusObject") abstract Status getStatus();
}

/// The descriptor of a health indicator: its status and details.
final class IndicatedHealthDescriptor : HealthDescriptor
{
    private Health health;

    /// The descriptor of `health`.
    this(Health health) pure nothrow @nogc
    {
        this.health = health;
    }

    /// `UP`, without details.
    static IndicatedHealthDescriptor UP()
    {
        return new IndicatedHealthDescriptor(Health.up().build());
    }

    @JsonIgnore @JsonProperty("statusObject") override Status getStatus()
    {
        return health.getStatus();
    }

    /// The status code, written as `status`.
    @JsonProperty("status") string getStatusCode()
    {
        return getStatus().getCode();
    }

    /// The status description, written as `description` when not empty.
    @JsonProperty("description") @nonEmpty string getStatusDescription()
    {
        return getStatus().getDescription();
    }

    /// The details, written when not empty.
    @nonEmpty LinkedHashMap!(string, Any) getDetails()
    {
        return health.getDetails();
    }
}

/// The descriptor of a composite: its aggregate status and, when shown, its components.
class CompositeHealthDescriptor : HealthDescriptor
{
    private ApiVersion apiVersion;
    private Status status;
    private LinkedHashMap!(string, HealthDescriptor) components;

    /// `status`, with `components` (or `null`) sorted by name.
    this(ApiVersion apiVersion, Status status, LinkedHashMap!(string, HealthDescriptor) components)
    {
        import std.algorithm.sorting : sort;

        this.apiVersion = apiVersion;
        this.status = status;
        if (components !is null)
        {
            auto names = components.keySet().toArray();
            sort(names);
            this.components = new LinkedHashMap!(string, HealthDescriptor);
            foreach (name; names)
                this.components.put(name, components.get(name));
        }
    }

    @JsonIgnore @JsonProperty("statusObject") override Status getStatus()
    {
        return status;
    }

    /// The status code, written as `status`.
    @JsonProperty("status") string getStatusCode()
    {
        return getStatus().getCode();
    }

    /// The status description, written as `description` when not empty.
    @JsonProperty("description") @nonEmpty string getStatusDescription()
    {
        return getStatus().getDescription();
    }

    /// The components, for API v3.
    @JsonIgnore @JsonProperty("componentsObject") LinkedHashMap!(string, HealthDescriptor) getComponents()
    {
        return apiVersion == ApiVersion.V3 ? components : null;
    }

    /// The components, for API v2.
    @JsonIgnore @JsonProperty("detailsObject") LinkedHashMap!(string, HealthDescriptor) getDetails()
    {
        return apiVersion == ApiVersion.V2 ? components : null;
    }

    /// `getComponents` as Jackson writes it: each value as its runtime class, `components` when not empty.
    @JsonProperty("components") @nonEmpty JsonMap getComponentsJson()
    {
        return runtimeTyped(getComponents());
    }

    /// `getDetails` as Jackson writes it, `details` when not empty.
    @JsonProperty("details") @nonEmpty JsonMap getDetailsJson()
    {
        return runtimeTyped(getDetails());
    }

    // flint.jackson writes a map's values as their declared type; Jackson writes HealthDescriptor values as their
    // runtime class.
    protected static LinkedHashMap!(string, Any) runtimeTyped(LinkedHashMap!(string, HealthDescriptor) map)
    {
        if (map is null)
            return null;
        auto result = new LinkedHashMap!(string, Any);
        foreach (name; map.keySet().toArray())
        {
            auto value = map.get(name);
            result.put(name, Any.ofObject(value, typeid(value).name));
        }
        return result;
    }
}

/// The descriptor of the whole system: a composite with the group names.
final class SystemHealthDescriptor : CompositeHealthDescriptor
{
    private string[] groups;

    /// The system's descriptor.
    this(ApiVersion apiVersion, Status status, LinkedHashMap!(string, HealthDescriptor) components, string[] groups)
    {
        super(apiVersion, status, components);
        this.groups = groups;
    }

    @JsonIgnore @JsonProperty("statusObject") override Status getStatus()
    {
        return super.getStatus();
    }

    /// The status code, written as `status`.
    @JsonProperty("status") override string getStatusCode()
    {
        return super.getStatusCode();
    }

    /// The status description, written as `description` when not empty.
    @JsonProperty("description") @nonEmpty override string getStatusDescription()
    {
        return super.getStatusDescription();
    }

    /// The components, for API v3.
    @JsonIgnore @JsonProperty("componentsObject") override LinkedHashMap!(string, HealthDescriptor) getComponents()
    {
        return super.getComponents();
    }

    /// The components, for API v2.
    @JsonIgnore @JsonProperty("detailsObject") override LinkedHashMap!(string, HealthDescriptor) getDetails()
    {
        return super.getDetails();
    }

    /// `components`, when not empty.
    @JsonProperty("components") @nonEmpty override JsonMap getComponentsJson()
    {
        return super.getComponentsJson();
    }

    /// `details`, when not empty.
    @JsonProperty("details") @nonEmpty override JsonMap getDetailsJson()
    {
        return super.getDetailsJson();
    }

    /// The group names, sorted, written when not empty.
    @nonEmpty string[] getGroups() pure nothrow @nogc
    {
        return groups;
    }
}

/// A group of health contributors the endpoint reports together, with its own visibility, aggregation and status
/// codes.
interface HealthEndpointGroup
{
    /// Whether the contributor named `name` (a `/`-separated path) belongs to the group.
    bool isMember(string name);

    /// Whether components are shown to `securityContext`.
    bool showComponents(const SecurityContext securityContext);

    /// Whether details are shown to `securityContext`.
    bool showDetails(const SecurityContext securityContext);

    /// The group's status aggregator.
    StatusAggregator getStatusAggregator();

    /// The group's HTTP status mapper.
    HttpCodeStatusMapper getHttpCodeStatusMapper();
}

/// The primary group and the named groups.
interface HealthEndpointGroups
{
    /// The group of the whole system.
    HealthEndpointGroup getPrimary();

    /// The names of the named groups.
    string[] getNames();

    /// The group named `name`, or `null`.
    HealthEndpointGroup get(string name);
}

/// The descriptor a lookup produced and the group that produced it.
struct HealthResult
{
    /// The descriptor.
    HealthDescriptor descriptor;
    /// The group.
    HealthEndpointGroup group;
}

/// Boot's `HealthEndpointSupport`, for the blocking registry.
abstract class HealthEndpointSupport
{
    private HealthContributorRegistry registry;
    private HealthEndpointGroups groups;

    /// Over `registry` and `groups`.
    protected this(HealthContributorRegistry registry, HealthEndpointGroups groups)
    {
        import flint.java.lang : IllegalArgumentException;

        if (registry is null)
            throw new IllegalArgumentException("'registry' must not be null");
        if (groups is null)
            throw new IllegalArgumentException("'groups' must not be null");
        this.registry = registry;
        this.groups = groups;
    }

    /// The health at `path`: a group (`path[0]`) or a contributor path; `HealthResult.init` when there is none.
    final HealthResult getResult(ApiVersion apiVersion, const SecurityContext securityContext,
            bool showAll, string[] path)
    {
        if (path.length)
        {
            if (auto group = groups.get(path[0]))
                return getResult(apiVersion, group, securityContext, showAll, path, 1);
        }
        return getResult(apiVersion, groups.getPrimary(), securityContext, showAll, path, 0);
    }

    private HealthResult getResult(ApiVersion apiVersion, HealthEndpointGroup group,
            const SecurityContext securityContext, bool showAll, string[] path, size_t pathOffset)
    {
        import std.algorithm.sorting : sort;
        import std.array : join;

        const showComponents = showAll || group.showComponents(securityContext);
        const showDetails = showAll || group.showDetails(securityContext);
        const isSystemHealth = group is groups.getPrimary() && pathOffset == 0;
        const isRoot = path.length == pathOffset;
        if (!showComponents && !isRoot)
            return HealthResult.init;
        HealthContributor contributor = registry;
        foreach (segment; path[pathOffset .. $])
        {
            auto composite = cast(CompositeHealthContributor) contributor;
            if (composite is null)
                return HealthResult.init;
            contributor = composite.getContributor(segment);
            if (contributor is null)
                return HealthResult.init;
        }
        string[] groupNames;
        if (isSystemHealth)
        {
            groupNames = groups.getNames().dup;
            sort(groupNames);
        }
        auto descriptor = getDescriptor(apiVersion, group, path[pathOffset .. $].join("/"),
                contributor, showComponents, showDetails, isSystemHealth, groupNames);
        return descriptor is null ? HealthResult.init : HealthResult(descriptor, group);
    }

    private HealthDescriptor getDescriptor(ApiVersion apiVersion, HealthEndpointGroup group, string name,
            HealthContributor contributor, bool showComponents, bool showDetails, bool system, string[] groupNames)
    {
        if (auto composite = cast(CompositeHealthContributor) contributor)
            return getAggregateDescriptor(apiVersion, group, name, composite, showComponents,
                    showDetails, system, groupNames);
        if (name.length == 0 || group.isMember(name))
        {
            auto health = (cast(HealthIndicator) contributor).health(showDetails);
            return health is null ? null : new IndicatedHealthDescriptor(health);
        }
        return null;
    }

    private HealthDescriptor getAggregateDescriptor(ApiVersion apiVersion, HealthEndpointGroup group, string name,
            CompositeHealthContributor contributor, bool showComponents, bool showDetails,
            bool system, string[] groupNames)
    {
        const prefix = name.length ? name ~ "/" : "";
        auto descriptors = new LinkedHashMap!(string, HealthDescriptor);
        Status[] statuses;
        foreach (child; contributor.getContributors())
        {
            auto descriptor = getDescriptor(apiVersion, group, prefix ~ child.name,
                    child.contributor, showComponents, showDetails, false, null);
            if (descriptor !is null)
            {
                descriptors.put(child.name, descriptor);
                statuses ~= descriptor.getStatus();
            }
        }
        if (descriptors.isEmpty())
            return null;
        auto status = group.getStatusAggregator().getAggregateStatus(statuses);
        auto components = showComponents ? descriptors : null;
        return system ? new SystemHealthDescriptor(apiVersion, status, components, groupNames)
            : new CompositeHealthDescriptor(apiVersion, status, components);
    }
}

/// The `health` endpoint: the system's health, a group's, or a contributor's.
class HealthEndpoint : HealthEndpointSupport
{
    /// `health`.
    static EndpointId ID()
    {
        return EndpointId.of("health");
    }

    /// Over `registry` and `groups`.
    this(HealthContributorRegistry registry, HealthEndpointGroups groups)
    {
        super(registry, groups);
    }

    /// The system's health; `UP` when no contributor is registered.
    HealthDescriptor health()
    {
        auto health = getResult(ApiVersion.V3, SecurityContext.NONE, true, null).descriptor;
        return health !is null ? health : IndicatedHealthDescriptor.UP;
    }

    /// The health at `path`, or `null`.
    HealthDescriptor healthForPath(string[] path...)
    {
        return getResult(ApiVersion.V3, SecurityContext.NONE, true, path.dup).descriptor;
    }
}

/// The health endpoint over HTTP: the status code follows the group's mapper; an unknown path is 404.
class HealthEndpointWebExtension : HealthEndpointSupport
{
    /// Over `registry` and `groups`.
    this(HealthContributorRegistry registry, HealthEndpointGroups groups)
    {
        super(registry, groups);
    }

    /// The response for `path` (empty for the system's health).
    WebEndpointResponse health(ApiVersion apiVersion, const SecurityContext securityContext,
            bool showAll, string[] path...)
    {
        auto result = getResult(apiVersion, securityContext, showAll, path.dup);
        if (result.descriptor is null)
            return path.length == 0 ? new WebEndpointResponse(body(IndicatedHealthDescriptor.UP),
                    WebEndpointResponse.STATUS_OK) : new WebEndpointResponse(Any.init,
                    WebEndpointResponse.STATUS_NOT_FOUND);
        const statusCode = result.group.getHttpCodeStatusMapper().getStatusCode(result.descriptor.getStatus());
        return new WebEndpointResponse(body(result.descriptor), statusCode);
    }

    // The body as its runtime class, which Jackson writes (Spring's serializer looks at the value's class too).
    private static Any body(HealthDescriptor descriptor)
    {
        return Any.ofObject(descriptor, typeid(descriptor).name);
    }
}
