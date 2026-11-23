/// Fixture for Flint AOT tests: `org.springframework.stereotype`.
module flint.stereotype;

import flint.core.annotation : AliasFor, ClassRef;

@safe:

/// `@Component`.
struct Component
{
    /// Bean name.
    string value;
}

/// `@Service`.
@Component
struct Service
{
    /// Bean name.
    @AliasFor(annotation : ClassRef("flint.stereotype.Component"))
    string value;
}

/// `@Repository`.
@Component
struct Repository
{
    /// Bean name.
    @AliasFor(annotation : ClassRef("flint.stereotype.Component"))
    string value;
}

/// `@Controller`.
@Component
struct Controller
{
    /// Bean name.
    @AliasFor(annotation : ClassRef("flint.stereotype.Component"))
    string value;
}
