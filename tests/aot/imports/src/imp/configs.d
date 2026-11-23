/// Scanned configurations importing others.
module imp.configs;

import flint.context.annotation : Bean, Configuration, Import, Profile;
import flint.core.annotation : ClassRef;
import shared_.things : Thing;

@safe:

/// Imports the shared configuration and the scanned one; its `thing` overrides the shared `thing` (gh-24643).
@Configuration @Import([ClassRef("shared_.things.SharedConfig"), ClassRef("imp.configs.ScannedConfig")])
class AlphaConfig
{
    /// Registered after the shared configuration's `thing`.
    @Bean Thing thing()
    {
        return new Thing("alpha");
    }
}

/// Scanned, and imported by `AlphaConfig`: defined once, as scanned.
@Configuration class ScannedConfig
{
    /// The scanned configuration's bean.
    @Bean Thing scannedThing()
    {
        return new Thing("scanned");
    }
}

/// Imports the shared configuration under a profile: the shared configuration registers if either importer did.
@Configuration @Profile(["beta"]) @Import([ClassRef("shared_.things.SharedConfig")])
class BetaConfig
{
}

/// `@Import` on an interface applies to its implementations (gh-34820).
@Import([ClassRef("shared_.things.MarkedConfig")])
interface Marked
{
}

/// Imports `MarkedConfig` through `Marked`.
@Configuration class GammaConfig : Marked
{
}
