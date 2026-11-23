/// Configurations outside the scanned package: registered only through `@Import`.
module shared_.things;

import flint.context.annotation : Bean, Configuration;

@safe:

/// A bean.
final class Thing
{
    /// Which configuration made it.
    string source;

    /// A thing from `source`.
    this(string source)
    {
        this.source = source;
    }
}

/// Imported by `AlphaConfig` and `BetaConfig`.
@Configuration class SharedConfig
{
    /// Overridden by `AlphaConfig.thing`.
    @Bean Thing thing()
    {
        return new Thing("shared");
    }
}

/// Imported through the `Marked` interface.
@Configuration class MarkedConfig
{
    /// The marked configuration's bean.
    @Bean Thing markedThing()
    {
        return new Thing("marked");
    }
}
