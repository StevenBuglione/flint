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

import flint.core.io : DefaultResourceLoader, Resource, ResourceLoader;
import flint.java.util : Locale;
import flint.util : Assert;
import std.typecons : Nullable;

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

// Ported from spring-framework v7.1.0, spring-core/src/main/java/org/springframework/core/io/support/LocalizedResourceHelper.java
// Modified by the Flint authors.

/// Selects a resource for a locale, falling back to the unlocalized resource.
class LocalizedResourceHelper
{
    enum DEFAULT_SEPARATOR = "_";

    private ResourceLoader resourceLoader;
    private string separator = DEFAULT_SEPARATOR;

    /// Creates a helper with the default loader.
    this()
    {
        this(new DefaultResourceLoader);
    }

    /// Creates a helper with the specified loader.
    this(ResourceLoader resourceLoader)
    {
        Assert.isTrue(resourceLoader !is null, "ResourceLoader must not be null");
        this.resourceLoader = resourceLoader;
    }

    /// Sets the separator between locale components. An absent separator restores the default.
    void setSeparator(Nullable!string separator)
    {
        this.separator = separator.isNull ? DEFAULT_SEPARATOR : separator.get();
    }

    /// Searches variant, country and language suffixes in order and returns the default handle when none exists.
    Resource findLocalizedResource(string name, string extension, Nullable!Locale locale)
    {
        Assert.isTrue(name !is null, "Name must not be null");
        Assert.isTrue(extension !is null, "Extension must not be null");

        Resource resource;
        if (!locale.isNull)
        {
            const language = locale.get().getLanguage();
            const country = locale.get().getCountry();
            const variant = locale.get().getVariant();

            if (variant.length)
                resource = resourceLoader.getResource(
                        name ~ separator ~ language ~ separator ~ country ~ separator ~ variant ~ extension);
            if ((resource is null || !resource.exists()) && country.length)
                resource = resourceLoader.getResource(name ~ separator ~ language ~ separator ~ country ~ extension);
            if ((resource is null || !resource.exists()) && language.length)
                resource = resourceLoader.getResource(name ~ separator ~ language ~ extension);
        }

        if (resource is null || !resource.exists())
            resource = resourceLoader.getResource(name ~ extension);
        return resource;
    }
}
