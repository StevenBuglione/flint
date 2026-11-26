/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from spring-framework v7.1.0, spring-core/src/test/java/org/springframework/core/io/support/ResourceRegionTests.java
// Modified by the Flint authors.

module core_io_resource_region_test;

import flint.core.io : DescriptiveResource, Resource;
import flint.core.io.support : ResourceRegion;
import flint.java.lang : IllegalArgumentException;
import std.exception : assertThrown;

@safe:

@("shouldThrowExceptionWithNullResource")
unittest
{
    assertThrown!IllegalArgumentException(new ResourceRegion(null, 0, 1));
}

@("shouldThrowExceptionForNegativePosition")
unittest
{
    Resource resource = new DescriptiveResource("unopened");
    assertThrown!IllegalArgumentException(new ResourceRegion(resource, -1, 1));
}

@("shouldThrowExceptionForNegativeCount")
unittest
{
    Resource resource = new DescriptiveResource("unopened");
    assertThrown!IllegalArgumentException(new ResourceRegion(resource, 0, -1));
}

@("retains the resource and range without opening it")
unittest
{
    Resource resource = new DescriptiveResource("unopened");
    auto region = new ResourceRegion(resource, long.max, 3);
    assert(region.getResource() is resource);
    assert(region.getPosition() == long.max);
    assert(region.getCount() == 3);
    assert(new ResourceRegion(resource, 0, 0).getCount() == 0);
}
