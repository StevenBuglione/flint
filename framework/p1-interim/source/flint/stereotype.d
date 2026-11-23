/++
Interim conformance copy of spring-context's `flint.stereotype` annotations (framework-core owns them;
deleted when `flint:context` lands).
+/
module flint.stereotype;

import flint.core.annotation : AliasFor;

@safe:

/// `@Component`.
struct Component
{
    string value; /// the suggested bean name
}

/// `@Controller`.
@Component struct Controller
{
    @AliasFor(annotation : classOfComponent) string value; ///
}

/// `@Service`.
@Component struct Service
{
    @AliasFor(annotation : classOfComponent) string value; ///
}

/// `@Repository`.
@Component struct Repository
{
    @AliasFor(annotation : classOfComponent) string value; ///
}

private enum classOfComponent = imported!"flint.core.annotation".ClassRef("flint.stereotype.Component");
