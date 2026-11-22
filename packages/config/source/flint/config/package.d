module flint.config;

import flint.arena : Error, Result, Status;
import flint.config.internal.bind : bind, check;
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

/// Validate an already bound value.
Error validateConfig(T)(scope const ref T configuration)
{
    return check(configuration);
}
