// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/AutoConfigurationSorterTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: test configuration classes are supplied to the AOT registry by the imports manifest.
module auto_order_candidates.configs;

import flint.boot.autoconfigure : AutoConfiguration, AutoConfigureAfter, AutoConfigureBefore, AutoConfigureOrder;
import flint.boot.context.properties : ClassRef;

@safe:

/// Uses the default order between the explicitly ordered classes.
@AutoConfigureOrder
class OrderUnspecified
{
}

/// Last among configurations ordered by priority alone.
@AutoConfigureOrder(int.max)
class OrderLowest
{
}

/// First among configurations ordered by priority alone.
@AutoConfigureOrder(int.min)
class OrderHighest
{
}

/// Must follow B.
@AutoConfigureAfter([ClassRef("auto_order_candidates.configs.AutoConfigureB")])
class AutoConfigureA
{
}

/// Uses B's name to declare the same ordering constraint.
@AutoConfigureAfter(name: ["auto_order_candidates.configs.AutoConfigureB"])
class AutoConfigureA2
{
}

/// Applies the direct @AutoConfiguration after attribute.
@AutoConfiguration(after: [ClassRef("auto_order_candidates.configs.AutoConfigureB2")])
final class AutoConfigureA3
{
}

/// Must follow C and any present D or E.
@AutoConfigureAfter([
    ClassRef("auto_order_candidates.configs.AutoConfigureC"),
    // The pinned acyclic cases omit D's metadata.
    ClassRef("auto_order_candidates.configs.AutoConfigureD"),
    ClassRef("auto_order_candidates.configs.AutoConfigureE")
])
class AutoConfigureB
{
}

/// Uses the direct after attribute to follow C.
@AutoConfiguration(after: [ClassRef("auto_order_candidates.configs.AutoConfigureC")])
final class AutoConfigureB2
{
}

/// An unordered prerequisite.
class AutoConfigureC
{
}

/// An optional prerequisite of B.
class AutoConfigureE
{
}

/// Must precede B in the mixed ordering graph.
@AutoConfigureBefore([ClassRef("auto_order_candidates.configs.AutoConfigureB")])
class AutoConfigureW
{
}

/// Uses B's name to declare the same ordering constraint.
@AutoConfigureBefore(name: ["auto_order_candidates.configs.AutoConfigureB"])
class AutoConfigureW2
{
}

/// Must follow Y.
class AutoConfigureX
{
}

/// Must precede X.
@AutoConfigureBefore([ClassRef("auto_order_candidates.configs.AutoConfigureX")])
class AutoConfigureY
{
}

/// Applies the direct @AutoConfiguration before attribute.
@AutoConfiguration(before: [ClassRef("auto_order_candidates.configs.AutoConfigureX")])
final class AutoConfigureY2
{
}

/// Must precede Y.
@AutoConfigureBefore([ClassRef("auto_order_candidates.configs.AutoConfigureY")])
class AutoConfigureZ
{
}

/// Uses the direct before attribute to precede Y2.
@AutoConfiguration(before: [ClassRef("auto_order_candidates.configs.AutoConfigureY2")])
final class AutoConfigureZ2
{
}
