/// Fixture for Flint AOT tests: `org.springframework.context.event`.
module flint.context.event;

import flint.core.annotation : AliasFor, ClassRef;

@safe:

/// `@EventListener`.
struct EventListener
{
    /// Alias for `classes`.
    @AliasFor("classes") ClassRef[] value;
    /// The event classes this listener handles; without them, the parameter's type.
    @AliasFor("value") ClassRef[] classes;
    /// SpEL condition.
    string condition;
}
