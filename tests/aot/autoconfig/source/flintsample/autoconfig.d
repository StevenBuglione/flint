/// Fixture auto-configurations: one the sample excludes, one it keeps.
module flintsample.autoconfig;

import flint.boot.autoconfigure : AutoConfiguration;
import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
import flint.context.annotation : Bean;

@safe:

/// A bean an auto-configuration provides.
class Widget
{
}

/// Left out by the sample's excludeName.
@AutoConfiguration
class ExcludedAutoConfiguration
{
    /// Never registered.
    @Bean
    Widget excludedWidget()
    {
        return new Widget;
    }
}

/// Kept; conditional on flint.boot.enableautoconfiguration at startup.
@AutoConfiguration
class WidgetAutoConfiguration
{
    /// Unless the application defines one.
    @Bean
    @ConditionalOnMissingBean
    Widget widget()
    {
        return new Widget;
    }
}
