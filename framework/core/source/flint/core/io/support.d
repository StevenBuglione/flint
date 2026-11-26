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
// Ported from spring-framework v7.1.0, spring-core/src/main/java/org/springframework/core/io/support/ResourceRegion.java
// Modified by the Flint authors.

module flint.core.io.support;

import flint.core.io : Resource;
import flint.util : Assert;

@safe:

/// A starting position and byte count within a resource.
class ResourceRegion
{
    private Resource resource;
    private long position;
    private long count;

    /// Creates a region without opening the resource. Throws IllegalArgumentException for invalid arguments.
    this(Resource resource, long position, long count)
    {
        Assert.isTrue(resource !is null, "Resource must not be null");
        Assert.isTrue(position >= 0, "'position' must be greater than or equal to 0");
        Assert.isTrue(count >= 0, "'count' must be greater than or equal to 0");
        this.resource = resource;
        this.position = position;
        this.count = count;
    }

    /// The resource that contains the region.
    Resource getResource()
    {
        return resource;
    }

    /// The starting position within the resource.
    long getPosition()
    {
        return position;
    }

    /// The length of the region in bytes.
    long getCount()
    {
        return count;
    }
}
