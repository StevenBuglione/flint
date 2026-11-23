/// Fixtures shared by the `*_upstream_test` ports of the Spring Boot binder tests: Boot's
/// `MockConfigurationPropertySource.nonIterable()` and the binding constructor descriptor Flint AOT emits.
module boot_tests.upstream_support;

import flint.boot.context.config : ConfigDataResourceReader;
import flint.boot.context.properties.bind : Binder, DefaultValue;
import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName,
    ConfigurationPropertySource, ConfigurationPropertyState, MapConfigurationPropertySource;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, Descriptor, MergedAnnotation,
    ParameterDescriptor, descriptorOf;
import flint.engine.aot.name : typeNameOf;

@safe:

/// A source of `entries` (pairs of key and value), as `MockConfigurationPropertySource`.
MapConfigurationPropertySource source(string[2][] entries)
{
    return new MapConfigurationPropertySource("test", entries);
}

/// `MockConfigurationPropertySource.nonIterable()`: answers lookups but cannot list its names.
final class NonIterableSource : ConfigurationPropertySource
{
    private MapConfigurationPropertySource map;

    /// A non-iterable view of `map`.
    this(MapConfigurationPropertySource map)
    {
        this.map = map;
    }

    ConfigurationProperty getConfigurationProperty(ConfigurationPropertyName name)
    {
        return map.getConfigurationProperty(name);
    }

    /// Part of the upstream test fixture.
    ConfigurationPropertyState containsDescendantOf(ConfigurationPropertyName)
    {
        return ConfigurationPropertyState.UNKNOWN;
    }

    /// Part of the upstream test fixture.
    ConfigurationPropertyName[] iterator()
    {
        return null;
    }

    string getUnderlyingSourceName()
    {
        return map.getUnderlyingSourceName();
    }
}

/// A binder over `sources` that knows the descriptors of `Types` and `descriptors`, as Flint AOT registers them.
Binder binderOf(Types...)(ConfigurationPropertySource[] sources, Descriptor[] descriptors...)
{
    auto b = new Binder(sources.dup);
    static foreach (T; Types)
        b.getDescriptors().add(descriptorOf!T());
    foreach (descriptor; descriptors)
        b.getDescriptors().add(descriptor);
    return b;
}

/// `@DefaultValue(values)` as a merged parameter annotation.
MergedAnnotation[] defaultValue(string[] values...)
{
    return [MergedAnnotation(typeNameOf!DefaultValue, Any.of(DefaultValue(values.dup)), 0)];
}

private Any construct(T, size_t overload)(scope Any[] arguments)
{
    import std.traits : Parameters;

    alias Params = Parameters!(__traits(getOverloads, T, "__ctor")[overload]);
    Params values;
    static foreach (i; 0 .. Params.length)
        values[i] = arguments[i].isNull() ? Params[i].init : arguments[i].get!(Params[i]);
    static if (is(T == class))
        return Any.of(new T(values));
    else
        return Any.of(T(values));
}

/// `T`'s descriptor with the binding constructor Flint AOT emits: constructor `overload`, with `annotations` per
/// parameter.
Descriptor valueObject(T, size_t overload = 0)(MergedAnnotation[][] annotations = null)
{
    import std.traits : ParameterIdentifierTuple, Parameters;

    alias ctor = __traits(getOverloads, T, "__ctor")[overload];
    alias Params = Parameters!ctor;
    static immutable names = [ParameterIdentifierTuple!ctor];
    auto descriptor = descriptorOf!T();
    ParameterDescriptor[] parameters;
    static foreach (i; 0 .. Params.length)
        parameters ~= ParameterDescriptor(names[i], typeNameOf!(Params[i]), i < annotations.length
                ? annotations[i] : null);
    descriptor.constructors = [ConstructorDescriptor(parameters, null, &construct!(T, overload))];
    return descriptor;
}

/// Config data resources in memory, keyed by path (the class path root is `resources`, `file:` paths are relative
/// to `.`), as boot_tests/config_data_test.d supplies them.
final class MemoryReader : ConfigDataResourceReader
{
    /// The files, by path.
    string[string] files;

    /// A reader of `files`.
    this(string[string] files)
    {
        this.files = files;
    }

    /// Part of the upstream test fixture.
    const(ubyte)[] read(string path)
    {
        if (auto content = path in files)
            return cast(const(ubyte)[])*content;
        return null;
    }

    /// Part of the upstream test fixture.
    string[] subdirectories(string directory)
    {
        import std.algorithm.searching : startsWith;
        import std.algorithm.sorting : sort;
        import std.string : indexOf;

        string[] result;
        foreach (path; files.keys)
        {
            if (!path.startsWith(directory ~ "/"))
                continue;
            const rest = path[directory.length + 1 .. $];
            const slash = rest.indexOf('/');
            if (slash > 0)
            {
                const sub = directory ~ "/" ~ rest[0 .. slash];
                bool seen;
                foreach (existing; result)
                    seen = seen || existing == sub;
                if (!seen)
                    result ~= sub;
            }
        }
        result.sort();
        return result;
    }

    /// Part of the upstream test fixture.
    bool directoryExists(string directory)
    {
        import std.algorithm.searching : startsWith;

        foreach (path; files.keys)
        {
            if (path.startsWith(directory ~ "/"))
                return true;
        }
        return false;
    }
}
