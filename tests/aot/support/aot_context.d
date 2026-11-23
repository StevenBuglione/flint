/// Test support for Flint AOT: a minimal application context over flint:engine-aot and the generated registry.
/// Not a product: it implements docs/spring/aot-contract.md section 5.4 only as far as the tests need.
module aot_context;

import flint.engine.aot.any : Any;
import flint.engine.aot.bean : BeanDefinition, BeanFactory, ScopeKind;
import flint.engine.aot.condition : ConditionContext;
import flint.engine.aot.descriptor : Descriptor;
import flint.engine.aot.event : EventListenerSpec;
import flint.engine.aot.mapping : ExceptionHandlerSpec, HandlerMapping;
import flint.engine.aot.query : DerivedQuery;
import flint.engine.aot.registry : AotRegistry;

@safe:

/// A started context.
final class AotContext : AotRegistry, BeanFactory, ConditionContext
{
    /// Everything the registry delivered.
    BeanDefinition[] definitions;
    /// ditto
    Descriptor[] descriptors;
    /// ditto
    HandlerMapping[] mappings;
    /// ditto
    ExceptionHandlerSpec[] exceptionHandlers;
    /// ditto
    EventListenerSpec[] listeners;
    /// ditto
    DerivedQuery[] queries;
    /// ditto
    string applicationType;
    /// Definitions whose conditions held, in rank order.
    BeanDefinition[] active;
    /// Creation order, for shutdown.
    string[] created;

    private string[] profiles;
    private string[string] properties;
    private Object[string] singletons;
    private Object[string] targets;
    private bool[string] creating;
    private Object[] extras;
    private string[] extraTypes;

    /// Profiles and properties.
    this(string[] profiles, string[string] properties)
    {
        this.profiles = profiles;
        this.properties = properties;
    }

    /// An object the context exposes by type without a definition, such as an Advisor.
    void provide(string type, Object instance)
    {
        extraTypes ~= type;
        extras ~= instance;
    }

    // ---- AotRegistry ----

    void begin(uint contractVersion, size_t modules) scope
    {
        if (contractVersion != 1)
            throw new Exception("contract version mismatch");
    }

    void bean(BeanDefinition definition) scope
    {
        definitions ~= definition;
    }

    void descriptor(Descriptor descriptor) scope
    {
        descriptors ~= descriptor;
    }

    void mapping(HandlerMapping mapping) scope
    {
        mappings ~= mapping;
    }

    void exceptionHandler(ExceptionHandlerSpec handler) scope
    {
        exceptionHandlers ~= handler;
    }

    void listener(EventListenerSpec listener) scope
    {
        listeners ~= listener;
    }

    void query(DerivedQuery query) scope
    {
        queries ~= query;
    }

    void application(string type, string[] scanPackages) scope
    {
        applicationType = type;
    }

    void end() scope
    {
    }

    /// Section 5.4: conditions in definition order (the registry's order), then singletons in that order.
    void refresh()
    {
        foreach (ref definition; definitions)
        {
            if (definition.condition is null || definition.condition(this))
                active ~= definition;
        }
        foreach (ref definition; active)
        {
            if (definition.scope_ == ScopeKind.singleton && !definition.lazyInit)
                getBean(definition.name);
        }
    }

    /// Destroy singletons in reverse creation order.
    void close()
    {
        foreach_reverse (name; created)
        {
            auto definition = find(name);
            if (definition !is null && definition.destroy !is null)
                definition.destroy(targets[name]);
        }
    }

    private BeanDefinition* find(string name) return
    {
        foreach (ref definition; active)
        {
            if (definition.name == name)
                return &definition;
        }
        return null;
    }

    // ---- BeanFactory ----

    Object getBean(string name)
    {
        if (auto existing = name in singletons)
            return *existing;
        auto definition = find(name);
        if (definition is null)
            throw new Exception("NoSuchBeanDefinitionException: No bean named '" ~ name ~ "' available");
        if (name in creating)
            throw new Exception("BeanCurrentlyInCreationException: " ~ name);
        creating[name] = true;
        scope (exit)
            creating.remove(name);
        foreach (dependency; definition.dependsOn)
            getBean(dependency);
        auto target = definition.create(this);
        if (definition.initialize !is null)
            definition.initialize(target, this);
        Object exposed = target;
        if (definition.proxy !is null)
            exposed = definition.proxy(target, this);
        if (definition.scope_ == ScopeKind.singleton)
        {
            singletons[name] = exposed;
            targets[name] = target;
            created ~= name;
        }
        return exposed;
    }

    private string[] candidates(string type, string qualifier)
    {
        import std.algorithm.searching : canFind;

        string[] names;
        foreach (ref definition; active)
        {
            if (definition.types.canFind(type) && (qualifier.length == 0
                    || definition.qualifiers.canFind(qualifier) || definition.name == qualifier))
                names ~= definition.name;
        }
        if (names.length > 1)
        {
            foreach (name; names)
            {
                if (find(name).primary)
                    return [name];
            }
        }
        return names;
    }

    Object getBeanOfType(string type, string qualifier = null)
    {
        auto names = candidates(type, qualifier);
        if (names.length == 0)
            throw new Exception("NoSuchBeanDefinitionException: No qualifying bean of type '" ~ type ~ "' available");
        if (names.length > 1)
            throw new Exception("NoUniqueBeanDefinitionException: " ~ type);
        return getBean(names[0]);
    }

    Object findBeanOfType(string type, string qualifier = null)
    {
        auto names = candidates(type, qualifier);
        if (names.length == 1)
            return getBean(names[0]);
        foreach (index, extra; extraTypes)
        {
            if (extra == type)
                return extras[index];
        }
        return null;
    }

    Object[] getBeansOfType(string type)
    {
        Object[] result;
        foreach (name; candidates(type, null))
            result ~= getBean(name);
        foreach (index, extra; extraTypes)
        {
            if (extra == type)
                result ~= extras[index];
        }
        return result;
    }

    Any resolveValue(string expression, string targetType)
    {
        import std.conv : to;
        import std.string : indexOf;

        string key = expression;
        string fallback;
        if (key.length > 3 && key[0 .. 2] == "${" && key[$ - 1] == '}')
        {
            key = key[2 .. $ - 1];
            const colon = key.indexOf(':');
            if (colon >= 0)
            {
                fallback = key[colon + 1 .. $];
                key = key[0 .. colon];
            }
        }
        const text = properties.get(key, fallback);
        switch (targetType)
        {
        case "int":
            return Any.of(text.to!int);
        case "long":
            return Any.of(text.to!long);
        case "bool":
            return Any.of(text == "true");
        default:
            return Any.of(text);
        }
    }

    void bind(string prefix, Any target)
    {
    }

    Any bindConstructor(string prefix, string type)
    {
        return Any.init;
    }

    // ---- ConditionContext ----

    bool acceptsProfile(string profile)
    {
        import std.algorithm.searching : canFind;

        return profiles.length ? profiles.canFind(profile) : profile == "default";
    }

    bool property(string name, string havingValue, bool matchIfMissing)
    {
        import std.uni : sicmp;

        auto value = name in properties;
        if (value is null)
            return matchIfMissing;
        return havingValue.length ? sicmp(*value, havingValue) == 0 : sicmp(*value, "false") != 0;
    }

    bool hasBeanOfType(string type)
    {
        import std.algorithm.searching : canFind;

        foreach (ref definition; active)
        {
            if (definition.types.canFind(type))
                return true;
        }
        return false;
    }

    bool hasBeanNamed(string name)
    {
        return find(name) !is null;
    }

    bool hasSingleCandidate(string type)
    {
        return candidates(type, null).length == 1;
    }

    bool isWebApplication(string type)
    {
        return true;
    }

    bool isAutoConfigurationExcluded(string type)
    {
        return false;
    }
}
