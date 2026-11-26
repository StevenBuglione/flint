// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/repository/{CrudRepository,ListCrudRepository,PagingAndSortingRepository,ListPagingAndSortingRepository}.java
// CrudRepository, PagingAndSortingRepository and ListPagingAndSortingRepository: Copyright 2008-present the original author or authors.
// ListCrudRepository: Copyright 2022-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.repository_runtime;

import flint.data.domain : Page, Pageable, Sort;
import flint.data.repository : NoRepositoryBean, Repository;
import flint.java.lang : ClassCastException, IllegalArgumentException, Iterable, NullPointerException;
import flint.java.util : ArrayList, Iterator, List, Optional;

@safe:

/// Operations for saving, retrieving and deleting persistent entities.
@NoRepositoryBean
interface CrudRepository(T, ID) : Repository!(T, ID)
{
    /// Returns the entity produced by the underlying write.
    T save(T entity);

    /// Returns the entity produced by the write with a checked subtype.
    S save(S)(S entity) if (isRepositorySubtype!(S, T))
    {
        return asRepositoryType!S(save(cast(T) entity));
    }

    /// Saves the input entities and returns the resulting entities.
    Iterable!T saveAll(Iterable!T entities);

    /// Uses one batch operation and checks each returned entity against S.
    Iterable!S saveAll(S)(Iterable!S entities) if (isRepositorySubtype!(S, T))
    {
        auto saved = saveAll(repositoryInput!T(entities));
        return new RepositoryIterable!(S, T)(saved);
    }

    /// Finds the entity with the given ID.
    Optional!T findById(ID id);

    /// Checks whether an entity has the given ID.
    bool existsById(ID id);

    /// Returns every entity.
    Iterable!T findAll();

    /// Returns entities with the requested IDs.
    Iterable!T findAllById(Iterable!ID ids);

    /// Returns the number of entities.
    long count();

    /// Deletes the entity with the given ID, if present.
    void deleteById(ID id);

    /// Deletes the given entity.
    void delete_(T entity);

    /// Deletes entities with the requested IDs.
    void deleteAllById(Iterable!ID ids);

    /// Accepts IDs derived from the repository's ID type.
    void deleteAllById(S)(Iterable!S ids) if (isRepositorySubtype!(S, ID))
    {
        deleteAllById(repositoryInput!ID(ids));
    }

    /// Deletes the given entities.
    void deleteAll(Iterable!T entities);

    /// Accepts entities derived from the repository's domain type.
    void deleteAll(S)(Iterable!S entities) if (isRepositorySubtype!(S, T))
    {
        deleteAll(repositoryInput!T(entities));
    }

    /// Deletes every entity.
    void deleteAll();
}

/// CRUD operations whose collection results are Java Lists.
@NoRepositoryBean
interface ListCrudRepository(T, ID) : CrudRepository!(T, ID)
{
    /// Saves the input entities and returns a list of the resulting entities.
    override List!T saveAll(Iterable!T entities);

    /// Returns a typed list in the order produced by a single backend batch.
    List!S saveAll(S)(Iterable!S entities) if (isRepositorySubtype!(S, T))
    {
        auto saved = saveAll(repositoryInput!T(entities));
        auto typed = new ArrayList!S(saved.size());
        foreach (entity; saved)
            typed.add(asRepositoryType!S(entity));
        return typed;
    }

    /// Returns every entity as a list.
    override List!T findAll();

    /// Returns a list of entities with the requested IDs.
    override List!T findAllById(Iterable!ID ids);
}

/// Repository methods for sorting and paging results.
@NoRepositoryBean
interface PagingAndSortingRepository(T, ID) : Repository!(T, ID)
{
    /// All entities in the given sort order.
    Iterable!T findAll(Sort sort);

    /// The entities that satisfy the requested page.
    Page!T findAll(Pageable pageable);
}

/// Returns sorted entities as a List and retains the pageable overload.
@NoRepositoryBean
interface ListPagingAndSortingRepository(T, ID) : PagingAndSortingRepository!(T, ID)
{
    alias findAll = PagingAndSortingRepository!(T, ID).findAll;

    /// All entities in the given sort order, in a List.
    override List!T findAll(Sort sort);
}

private enum bool isRepositorySubtype(S, T) = (is(S == class) || is(S == interface)) && is(S : T) && !is(S == T);

private T asRepositoryType(T, S)(S value)
{
    static if (is(S : T))
    {
        return value;
    }
    else
    {
        auto converted = cast(T) value;
        if (converted is null && value !is null)
            throw new ClassCastException("Saved entity does not have the requested subtype");
        return converted;
    }
}

private Iterable!T repositoryInput(T, S)(Iterable!S values)
{
    if (values is null)
        throw new IllegalArgumentException("Repository input must not be null");
    return new RepositoryIterable!(T, S)(values);
}

private final class RepositoryIterable(T, S) : Iterable!T
{
    private Iterable!S source;

    this(Iterable!S source)
    {
        this.source = source;
    }

    override Iterator!T iterator()
    {
        return new RepositoryIterator!(T, S)(source.iterator());
    }

    override void forEach(void delegate(T) @safe action)
    {
        if (action is null)
            throw new NullPointerException("Action must not be null");
        foreach (value; source)
            action(asRepositoryType!T(value));
    }

    override int opApply(scope int delegate(T) @safe action)
    {
        foreach (value; source)
        {
            const result = action(asRepositoryType!T(value));
            if (result != 0)
                return result;
        }
        return 0;
    }
}

private final class RepositoryIterator(T, S) : Iterator!T
{
    private Iterator!S source;

    this(Iterator!S source)
    {
        this.source = source;
    }

    override bool hasNext()
    {
        return source.hasNext();
    }

    override T next()
    {
        return asRepositoryType!T(source.next());
    }

    override void remove()
    {
        source.remove();
    }
}
