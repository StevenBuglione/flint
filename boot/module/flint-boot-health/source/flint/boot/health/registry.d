// Ported from spring-boot v4.2.0: module/spring-boot-health/src/main/java/org/springframework/boot/health/registry/HealthContributorRegistry.java
// with DefaultHealthContributorRegistry.java and AbstractRegistry.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the registry is not synchronised: contributors are registered at startup.

/// `org.springframework.boot.health.registry`: the registry of health contributors.
module flint.boot.health.registry;

import flint.boot.health.contributor : CompositeHealthContributor, HealthContributor, NamedContributor;

@safe:

/// The application's named health contributors.
interface HealthContributorRegistry : CompositeHealthContributor
{
    /// Register `contributor` as `name`. Throws `IllegalStateException` when the name is taken.
    void registerContributor(string name, HealthContributor contributor);

    /// Remove the contributor named `name`; returns it, or `null`.
    HealthContributor unregisterContributor(string name);
}

/// The default registry: contributors in registration order.
class DefaultHealthContributorRegistry : HealthContributorRegistry
{
    private NamedContributor[] contributors;

    /// With `contributors`.
    this(NamedContributor[] contributors = null)
    {
        foreach (item; contributors)
            registerContributor(item.name, item.contributor);
    }

    /// Register `contributor` as `name`.
    void registerContributor(string name, HealthContributor contributor)
    {
        import flint.java.lang : IllegalArgumentException, IllegalStateException;

        if (name.length == 0)
            throw new IllegalArgumentException("'name' must not be empty");
        if (contributor is null)
            throw new IllegalArgumentException("'contributor' must not be null");
        if (getContributor(name) !is null)
            throw new IllegalStateException("A contribution named '" ~ name ~ "' has already been registered");
        contributors ~= NamedContributor(name, contributor);
    }

    /// Remove the contributor named `name`.
    HealthContributor unregisterContributor(string name)
    {
        foreach (index, item; contributors)
        {
            if (item.name == name)
            {
                contributors = contributors[0 .. index] ~ contributors[index + 1 .. $];
                return item.contributor;
            }
        }
        return null;
    }

    /// The contributor named `name`, or `null`.
    HealthContributor getContributor(string name)
    {
        foreach (item; contributors)
        {
            if (item.name == name)
                return item.contributor;
        }
        return null;
    }

    /// The contributors, in registration order.
    NamedContributor[] getContributors()
    {
        return contributors.dup;
    }
}
