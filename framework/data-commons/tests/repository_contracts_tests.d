module repository_contracts_tests;

import flint.data.domain : Page, PageImpl, PageRequest, Pageable, Sort;
import flint.data.repository : NoRepositoryBean, Repository, RepositoryDefinition;
import flint.data.repository_runtime : CrudRepository, ListCrudRepository,
    ListPagingAndSortingRepository, PagingAndSortingRepository;
import flint.engine.aot.descriptor : descriptorOf;
import flint.java.classref : classOf;
import flint.java.lang : ClassCastException, Iterable;
import flint.java.util : List, Optional;
import flint.stereotype : Indexed;
import std.exception : assertThrown;

@safe:

private class Owner
{
}

private final class PremiumOwner : Owner
{
}

@NoRepositoryBean
private interface BaseOwners : Repository!(Owner, long)
{
}

private final class Writes : ListCrudRepository!(Owner, long)
{
    private Owner saved;
    private List!Owner savedBatch;
    private Owner[] inputs;
    private int batchCalls;

    override Owner save(Owner entity)
    {
        return saved;
    }

    override List!Owner saveAll(Iterable!Owner entities)
    {
        ++batchCalls;
        inputs = null;
        foreach (entity; entities)
            inputs ~= entity;
        return savedBatch;
    }

    override Optional!Owner findById(long id)
    {
        return id == 1 ? Optional!Owner.of(saved) : Optional!Owner.empty();
    }

    override bool existsById(long id)
    {
        return findById(id).isPresent();
    }

    override List!Owner findAll()
    {
        return savedBatch;
    }

    override List!Owner findAllById(Iterable!long ids)
    {
        return savedBatch;
    }

    override long count()
    {
        return savedBatch.size();
    }

    override void deleteById(long id)
    {
    }

    override void delete_(Owner entity)
    {
    }

    override void deleteAllById(Iterable!long ids)
    {
    }

    override void deleteAll(Iterable!Owner entities)
    {
    }

    override void deleteAll()
    {
    }
}

@RepositoryDefinition(classOf!Owner, classOf!long)
private interface DeclaredOwners
{
}

private final class Owners : ListPagingAndSortingRepository!(Owner, long)
{
    private Owner owner;
    private Sort seenSort;
    private Pageable seenPage;

    this(Owner owner)
    {
        this.owner = owner;
    }

    override List!Owner findAll(Sort sort)
    {
        seenSort = sort;
        return List!Owner.of(owner);
    }

    override Page!Owner findAll(Pageable pageable)
    {
        seenPage = pageable;
        return new PageImpl!Owner(List!Owner.of(owner), pageable, 1);
    }
}

@("Repository metadata is retained for the build-time discovery inputs")
unittest
{
    static assert(is(BaseOwners : Repository!(Owner, long)));
    static assert(!__traits(compiles, imported!"flint.data.repository".CrudRepository!(Owner, long)));
    static assert(classOf!NoRepositoryBean.name == "flint.data.repository.NoRepositoryBean");
    static assert(classOf!RepositoryDefinition.name == "flint.data.repository.RepositoryDefinition");
    auto repository = descriptorOf!(Repository!(Owner, long))();
    assert(repository.annotation(classOf!Indexed.name) !is null);
    auto base = descriptorOf!BaseOwners();
    const marker = base.annotation(classOf!NoRepositoryBean.name);
    assert(marker !is null && marker.aggregateIndex == 0);

    auto annotated = descriptorOf!DeclaredOwners().annotation(classOf!RepositoryDefinition.name);
    assert(annotated !is null);
    const definition = annotated.value.get!RepositoryDefinition();
    assert(definition.domainClass == classOf!Owner && definition.idClass == classOf!long);
}

@("The list sorting contract overrides the iterable return and preserves page dispatch")
unittest
{
    auto owner = new Owner;
    auto implementation = new Owners(owner);
    ListPagingAndSortingRepository!(Owner, long) lists = implementation;
    PagingAndSortingRepository!(Owner, long) pages = lists;
    auto sort = Sort.by("id");
    auto pageable = PageRequest.of(0, 4);

    List!Owner result = lists.findAll(sort);
    Iterable!Owner iterable = pages.findAll(sort);
    assert(result.get(0) is owner && iterable.iterator().next() is owner);
    assert(implementation.seenSort is sort);

    auto page = lists.findAll(pageable);
    assert(page.getContent().get(0) is owner && page.getTotalElements() == 1);
    assert(implementation.seenPage is pageable);
}

@("CRUD subtype dispatch returns the saved object and checks incompatible results")
unittest
{
    auto supplied = new PremiumOwner;
    auto saved = new PremiumOwner;
    auto implementation = new Writes;
    implementation.saved = saved;
    CrudRepository!(Owner, long) repository = implementation;

    assert(repository.save(supplied) is saved);
    const PremiumOwner typed = repository.save!PremiumOwner(supplied);
    assert(typed is saved && typed !is supplied);

    implementation.saved = new Owner;
    assertThrown!ClassCastException(repository.save!PremiumOwner(supplied));
}

@("Saving a list of subtypes uses one batch and keeps saved entity order and identity")
unittest
{
    auto first = new PremiumOwner;
    auto second = new PremiumOwner;
    auto savedFirst = new PremiumOwner;
    auto savedSecond = new PremiumOwner;
    auto implementation = new Writes;
    implementation.savedBatch = List!Owner.of(savedFirst, savedSecond);
    ListCrudRepository!(Owner, long) lists = implementation;
    CrudRepository!(Owner, long) iterable = lists;

    auto list = lists.saveAll!PremiumOwner(List!PremiumOwner.of(first, second));
    assert(implementation.batchCalls == 1);
    assert(implementation.inputs[0] is first && implementation.inputs[1] is second);
    assert(list.size() == 2 && list.get(0) is savedFirst && list.get(1) is savedSecond);

    const saved = iterable.saveAll(List!Owner.of(first, second));
    assert(implementation.batchCalls == 2 && saved is implementation.savedBatch);
    assert(iterable.findAll() is implementation.savedBatch);

    auto projected = iterable.saveAll!PremiumOwner(List!PremiumOwner.of(first, second)).iterator();
    assert(implementation.batchCalls == 3);
    assert(projected.next() is savedFirst && projected.next() is savedSecond && !projected.hasNext());
}
