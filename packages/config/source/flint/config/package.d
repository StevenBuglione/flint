module flint.config;

import flint.arena : Error, Result, Status;
import flint.config.internal.bind : bind, bindAll, check;
import flint.config.internal.layers : Layers, loadLayers;
public import flint.config.types : ConfigurationProperties, ConfigOptions, Default, Diagnostic, Env, Required, Secret;

@safe:

/// Resolve startup configuration from the configured source layers.
Result!T load(T)(scope const ref ConfigOptions options)
{
    Layers layers;
    const failure = loadLayers(options, layers);
    if (failure.code != Status.ok)
        return Result!T(T.init, failure);
    Result!T result;
    result.error = bind(result.value, layers, layers.envPrefix, options.rejectUnknownKeys);
    if (!result.ok)
        result.value = T.init;
    return result;
}

/// Bind several `@ConfigurationProperties` types from one snapshot of the same sources.
///
/// The types may share files, `.env`, the environment and `--set` overrides. With
/// `rejectUnknownKeys`, a key is unknown only when none of the bound types claims it.
/// On failure every value is reset to its initializer and the earliest diagnostic by
/// key is returned, as for `load!T`.
Error load(T...)(scope const ref ConfigOptions options, ref T values) if (T.length != 0)
{
    Layers layers;
    auto failure = loadLayers(options, layers);
    if (failure.code == Status.ok)
        failure = bindAll(layers, options.rejectUnknownKeys, values);
    if (failure.code != Status.ok)
    {
        static foreach (index; 0 .. T.length)
            values[index] = T[index].init;
    }
    return failure;
}

/// Validate an already bound value.
Error validateConfig(T)(scope const ref T configuration)
{
    return check(configuration);
}
