// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/AutoConfigurationSorterTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: test configuration classes are supplied to the AOT registry by the imports manifest.
module auto_order_candidates.configs;

import flint.boot.autoconfigure : AutoConfigureAfter, AutoConfigureBefore, AutoConfigureOrder;
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

/// Must follow C and any present D or E.
@AutoConfigureAfter([
    ClassRef("auto_order_candidates.configs.AutoConfigureC"),
    ClassRef("auto_order_candidates.configs.AutoConfigureD"),
    ClassRef("auto_order_candidates.configs.AutoConfigureE")
])
class AutoConfigureB
{
}

/// An unordered prerequisite.
class AutoConfigureC
{
}

/// A prerequisite omitted from the acyclic test inputs.
@AutoConfigureAfter([ClassRef("auto_order_candidates.configs.AutoConfigureA")])
class AutoConfigureD
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

/// Must precede Y.
@AutoConfigureBefore([ClassRef("auto_order_candidates.configs.AutoConfigureY")])
class AutoConfigureZ
{
}
