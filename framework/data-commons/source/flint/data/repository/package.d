// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/repository/{NoRepositoryBean,Repository,RepositoryDefinition}.java
// NoRepositoryBean: Copyright 2008-present the original author or authors.
// Repository and RepositoryDefinition: Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.repository;

import flint.java.classref : ClassRef;
import flint.stereotype : Indexed;

@safe:

/// Excludes an intermediate repository interface from bean creation.
struct NoRepositoryBean
{
}

/// Declares the domain and ID type without extending the Repository interface.
struct RepositoryDefinition
{
    /// The repository's domain type.
    ClassRef domainClass;

    /// The type of its entity ID.
    ClassRef idClass;
}

/// Marks a repository that manages the domain type T with identifier type ID.
@Indexed
interface Repository(T, ID)
{
}
