// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/concurrent/ConcurrentMapCache.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.cache.concurrent;

import core.atomic : atomicLoad, atomicStore;
import core.sync.mutex : Mutex;
import core.thread.fiber : Fiber;
import core.thread.osthread : Thread;
import flint.cache : Cache, CacheManager;
import flint.cache.support : CacheNames, SimpleValueWrapper;
import flint.conc : Deadline;
import flint.conc.park : park, wakeAll;
import flint.conc.slot : ProcessSlot;
import flint.engine.aot.any : Any;
import flint.engine.aot.objects : objectEquals, objectToHash;
import flint.engine.reactor : Reactor, RemoteWaker;
import flint.java.io : IOException;
import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException;
import flint.java.util : Collection;
import flint.java.util.concurrent.callable : Callable;

@safe:

/// A process-local cache with atomic insertion and synchronous, per-key loading.
/// Strings are copied when retained. Other references, including references inside boxed values,
/// must have GC-managed or static storage and be safe to share with readers.
/// Writes copy the affected bucket in a fixed 64-bucket table, so their cost grows with that bucket's occupancy.
/// A single mutex per cache serializes publication and invalidation.
/// A cancelled reactor task waiting for another caller's load receives $(D IOException).
/// The loader remains governed by its own caller's task.
class ConcurrentMapCache : Cache
{
    private string name_;
    private bool allowNullValues;
    private Store store;

    /// Create an empty cache. By default it accepts null values and stores values by reference.
    this(string name, bool allowNullValues = true)
    {
        if (name is null)
            throw new IllegalArgumentException("Name must not be null");
        name_ = ownString(name);
        this.allowNullValues = allowNullValues;
        store = new Store();
    }

    /// Whether null values can be stored.
    final bool isAllowNullValues() nothrow @nogc
    {
        return allowNullValues;
    }

    /// Whether entries are stored as copies.
    final bool isStoreByValue() nothrow @nogc
    {
        return false;
    }

    override final string getName() nothrow @nogc
    {
        return name_;
    }

    override final Object getNativeCache() nothrow @nogc
    {
        return store;
    }

    /// The cached value as the requested type.
    T get(T)(Any key)
    {
        return (cast(Cache) this).get!T(key);
    }

    /// Read the value or call the typed loader on a miss (R9).
    T get(T)(Any key, Callable!T valueLoader)
    {
        return (cast(Cache) this).get(key, valueLoader);
    }

    override ValueWrapper get(Any key)
    {
        return lookup(bucketFor(store.table.get(), key), key).value;
    }

    override Any get(Any key, scope Any delegate() @safe valueLoader)
    {
        Flight started;
        for (;;)
        {
            auto table = store.table.get();
            auto slot = &bucketFor(table, key);
            auto previous = lookup(*slot, key);
            if (previous.value !is null)
                return previous.value.get();
            if (previous.flight !is null)
            {
                previous.flight.awaitCompletion();
                continue;
            }

            if (started is null)
            {
                key = ownedText(key);
                started = new Flight();
            }
            if (!store.change(table, *slot, key, Entry(key, null, started), Mutation.insert, previous))
                continue;
            if (previous.flight !is null || previous.value !is null)
                continue;

            scope (exit)
                started.complete();

            try
            {
                if (valueLoader is null)
                    throw new NullPointerException();
                auto value = valueLoader();
                checkValue(value);
                value = ownedText(value);
                auto wrapper = new SimpleValueWrapper(value);
                store.change(table, *slot, key, Entry(key, wrapper), Mutation.finish, previous, started);
                return value;
            }
            catch (Exception failure)
            {
                store.change(table, *slot, key, Entry.init, Mutation.finish, previous, started);
                throw new ValueRetrievalException(key, valueLoader, failure);
            }
        }
    }

    override void put(Any key, Any value)
    {
        checkValue(value);
        auto entry = Entry(ownedText(key), new SimpleValueWrapper(ownedText(value)));
        store.replace(key, entry);
    }

    override ValueWrapper putIfAbsent(Any key, Any value)
    {
        checkValue(value);
        SimpleValueWrapper wrapper;
        for (;;)
        {
            auto table = store.table.get();
            auto slot = &bucketFor(table, key);
            auto previous = lookup(*slot, key);
            if (previous.value !is null)
                return previous.value;
            if (previous.flight is null)
            {
                if (wrapper is null)
                {
                    key = ownedText(key);
                    wrapper = new SimpleValueWrapper(ownedText(value));
                }
                if (!store.change(table, *slot, key, Entry(key, wrapper), Mutation.insert, previous))
                    continue;
                if (previous.flight is null)
                    return previous.value;
            }
            previous.flight.awaitCompletion();
        }
    }

    override void evict(Any key)
    {
        evictIfPresent(key);
    }

    override bool evictIfPresent(Any key)
    {
        return store.replace(key, Entry.init).value !is null;
    }

    override void clear()
    {
        invalidate();
    }

    override bool invalidate()
    {
        auto previous = store.reset();
        foreach (ref bucket; previous.buckets)
            foreach (ref entry; entries(bucket.get()))
                if (entry.value !is null)
                    return true;
        return false;
    }

    private void checkValue(Any value)
    {
        if (!allowNullValues && value.isNull())
            throw new IllegalArgumentException(
                    "Cache '" ~ name_ ~ "' is configured to not allow null values" ~ " but null was provided");
    }
}

private Any ownedText(Any value)
{
    return value.typeName() == "string" ? Any.of(ownString(value.get!string())) : value;
}

private string ownString(string text)
{
    if (text is null)
        return null;
    return text.length == 0 ? "" : text.idup;
}

// Readers see one immutable bucket. A write copies only that bucket and replaces it atomically. A clear swaps the
// entire table so a loader admitted before the clear can finish for its caller without repopulating the cache.
private final class Store
{
    shared ProcessSlot!Table table;
    private Mutex writes;

    this()
    {
        writes = new Mutex();
        table.set(new Table());
    }

    Table reset()
    {
        auto next = new Table();
        writes.lock_nothrow();
        scope (exit)
            writes.unlock_nothrow();
        auto previous = table.get();
        table.set(next);
        return previous;
    }

    Entry replace(Any key, Entry replacement)
    {
        Entry previous;
        for (;;)
        {
            auto current = table.get();
            if (change(current, bucketFor(current, key), key, replacement, Mutation.replace, previous))
                return previous;
        }
    }

    // False means invalidation detached the table before this change could publish.
    bool change(Table admitted, ref shared ProcessSlot!Bucket slot, Any key, Entry replacement,
            Mutation mutation, out Entry previous, Flight owner = null)
    {
        for (;;)
        {
            auto observed = slot.get();
            auto current = entries(observed);
            auto index = owner is null ? find(current, key) : findOwner(current, owner);
            const present = index != current.length;
            previous = present ? current[index] : Entry.init;
            const removing = replacement.value is null && replacement.flight is null;
            if ((mutation == Mutation.insert && present) || (!present && (mutation == Mutation.finish || removing)))
                return true;

            auto next = updatedBucket(current, index, replacement);
            writes.lock_nothrow();
            scope (exit)
                writes.unlock_nothrow();
            if (table.get() !is admitted)
                return false;
            if (slot.get() is observed)
            {
                slot.set(next);
                return true;
            }
        }
    }
}

private final class Table
{
    shared ProcessSlot!Bucket[64] buckets;
}

private final class Bucket
{
    Entry[] items;

    this(Entry[] items) nothrow @nogc
    {
        this.items = items;
    }
}

private struct Entry
{
    Any key;
    Cache.ValueWrapper value;
    Flight flight;
}

private enum Mutation
{
    insert,
    replace,
    finish,
}

private ref shared(ProcessSlot!Bucket) bucketFor(Table table, Any key)
{
    if (key.isNull())
        throw new NullPointerException();
    auto object = key.asObject();
    auto hash = object is null ? key.toHash() : objectToHash(object);
    return table.buckets[hash % table.buckets.length];
}

private Entry[] entries(Bucket bucket) nothrow @nogc
{
    return bucket is null ? null : bucket.items;
}

private size_t find(Entry[] items, Any key)
{
    auto object = key.asObject();
    foreach (i, ref item; items)
    {
        if (object is null ? item.key == key : objectEquals(object, item.key.asObject()))
            return i;
    }
    return items.length;
}

private Entry lookup(ref shared ProcessSlot!Bucket slot, Any key)
{
    auto snapshot = entries(slot.get());
    auto index = find(snapshot, key);
    return index == snapshot.length ? Entry.init : snapshot[index];
}

private size_t findOwner(Entry[] items, Flight owner) nothrow @nogc
{
    foreach (i, ref item; items)
        if (item.flight is owner)
            return i;
    return items.length;
}

private Bucket updatedBucket(Entry[] current, size_t index, Entry replacement)
{
    const present = index != current.length;
    Entry[] updated;
    if (replacement.value is null && replacement.flight is null)
        updated = current[0 .. index] ~ current[index + 1 .. $];
    else if (present)
    {
        updated = current.dup;
        updated[index] = replacement;
    }
    else
        updated = current ~ replacement;
    return updated.length == 0 ? null : new Bucket(updated);
}

// The mutex serializes publication only. Readers use the shared slot directly, and hashing, equality and
// allocation happen before acquiring the writer mutex.
private bool publish(T)(ref shared ProcessSlot!T slot, Mutex writes, T expected, T next) nothrow @nogc
{
    writes.lock_nothrow();
    scope (exit)
        writes.unlock_nothrow();
    if (slot.get() !is expected)
        return false;
    slot.set(next);
    return true;
}

// Only a contended load waits. Protect registrations briefly and run the loader outside this mutex. Reactor
// fibers use the owner loop's wait handle so a loader can yield without blocking any reactor thread.
private final class Flight
{
    private Thread thread;
    private Fiber fiber;
    private Mutex gate;
    private RemoteWaker[] waiters;
    private shared uint completed;

    this()
    {
        thread = Thread.getThis();
        fiber = Fiber.getThis();
        gate = new Mutex();
    }

    void awaitCompletion()
    {
        if (thread is Thread.getThis() && fiber is Fiber.getThis())
            throw new IllegalStateException("Recursive cache load for the same key");

        auto reactor = Reactor.current();
        auto task = reactor.currentTask();
        if (task.ok())
            waitOnFiber(reactor, task.value.cancellation.deadline());
        else if (reactor.currentCore() != uint.max)
            throw new IllegalStateException("A cache load cannot wait on a reactor outside a task fiber");
        else
        {
            while (atomicLoad(completed) == 0)
                park(completed, 0, 1_000_000_000L);
        }
    }

    private void waitOnFiber(ref Reactor reactor, Deadline deadline)
    {
        // Reactor waits need a finite deadline even when only completion or cancellation can end the wait.
        if (deadline.monotonicNanoseconds == Deadline.none.monotonicNanoseconds)
            deadline = Deadline.afterMillis(ulong.max);
        gate.lock_nothrow();
        if (atomicLoad(completed) != 0)
        {
            gate.unlock_nothrow();
            return;
        }
        auto armed = reactor.armRemoteWake();
        if (!armed.ok())
        {
            gate.unlock_nothrow();
            throw new IllegalStateException(armed.error.message);
        }
        auto waker = armed.value;
        waiters ~= waker;
        gate.unlock_nothrow();

        auto result = reactor.yieldUntil(deadline);
        removeWaiter(waker);
        if (result.code != typeof(result.code).ok)
        {
            if (result.code == typeof(result.code).cancelled)
                throw new IOException(result.message);
            throw new IllegalStateException(result.message);
        }
    }

    private void removeWaiter(RemoteWaker waker) nothrow @nogc
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        foreach (i, ref candidate; waiters)
            if (candidate.ownerCore == waker.ownerCore && candidate.wait == waker.wait)
            {
                candidate = waiters[$ - 1];
                waiters[$ - 1] = RemoteWaker.init;
                waiters = waiters[0 .. $ - 1];
                return;
            }
    }

    void complete()
    {
        gate.lock_nothrow();
        atomicStore(completed, 1u);
        auto waiting = waiters;
        waiters = null;
        gate.unlock_nothrow();
        wakeAll(completed);
        foreach (waker; waiting)
            waker.signal();
    }
}

/// A manager for dynamically discovered or statically configured ConcurrentMapCache regions.
class ConcurrentMapCacheManager : CacheManager
{
    private shared ProcessSlot!Regions regions;
    private Mutex writes;
    private CacheNames names;

    /// Create a dynamic manager with no regions.
    this()
    {
        writes = new Mutex();
        regions.set(new Regions(null, true, true));
        names = new CacheNames(&registeredCaches, true);
    }

    /// Create a static manager for the given names.
    this(string[] cacheNames...)
    {
        this();
        configureCacheNames(cacheNames, false);
    }

    /// Configured regions are replaced. A null collection enables dynamic creation.
    void setCacheNames(Collection!string cacheNames)
    {
        configureCacheNames(cacheNames is null ? null : cacheNames.toArray(), cacheNames is null);
    }

    private void configureCacheNames(scope string[] requested, bool dynamic)
    {
        for (;;)
        {
            auto previous = regions.get();
            auto caches = previous.caches.dup;
            foreach (name; requested)
            {
                auto replacement = new ConcurrentMapCache(name, previous.allowNulls);
                auto index = regionIndex(caches, name);
                if (index == caches.length)
                    caches ~= replacement;
                else
                    caches[index] = replacement;
            }
            if (publish(regions, writes, previous, new Regions(caches, dynamic, previous.allowNulls)))
                return;
        }
    }

    /// Return whether newly created regions accept null values.
    bool isAllowNullValues() nothrow @nogc
    {
        return regions.get().allowNulls;
    }

    /// Reset the registered regions with the new null-value setting.
    void setAllowNullValues(bool allowNullValues)
    {
        for (;;)
        {
            auto previous = regions.get();
            if (allowNullValues == previous.allowNulls)
                return;
            auto caches = new Cache[previous.caches.length];
            foreach (i, cache; previous.caches)
                caches[i] = new ConcurrentMapCache(cache.getName(), allowNullValues);
            if (publish(regions, writes, previous, new Regions(caches, previous.dynamic, allowNullValues)))
                return;
        }
    }

    override Cache getCache(string name)
    {
        if (name is null)
            throw new NullPointerException();
        for (;;)
        {
            auto previous = regions.get();
            auto index = regionIndex(previous.caches, name);
            if (index != previous.caches.length)
                return previous.caches[index];
            if (!previous.dynamic)
                return null;

            auto cache = new ConcurrentMapCache(name, previous.allowNulls);
            auto next = new Regions(previous.caches ~ cache, previous.dynamic, previous.allowNulls);
            if (publish(regions, writes, previous, next))
                return cache;
        }
    }

    override Collection!string getCacheNames() nothrow @nogc
    {
        return names;
    }

    override void resetCaches()
    {
        for (;;)
        {
            auto previous = regions.get();
            foreach (cache; previous.caches)
                cache.clear();
            if (!previous.dynamic || publish(regions, writes, previous, new Regions(null, true, previous.allowNulls)))
                return;
        }
    }

    /// Remove the named region.
    void removeCache(string name)
    {
        if (name is null)
            throw new NullPointerException();
        for (;;)
        {
            auto previous = regions.get();
            auto index = regionIndex(previous.caches, name);
            if (index == previous.caches.length)
                return;
            auto caches = previous.caches[0 .. index] ~ previous.caches[index + 1 .. $];
            if (publish(regions, writes, previous, new Regions(caches, previous.dynamic, previous.allowNulls)))
                return;
        }
    }

    private Cache[] registeredCaches() nothrow @nogc
    {
        return regions.get().caches;
    }
}

private final class Regions
{
    Cache[] caches;
    bool dynamic;
    bool allowNulls;

    this(Cache[] caches, bool dynamic, bool allowNulls) nothrow @nogc
    {
        this.caches = caches;
        this.dynamic = dynamic;
        this.allowNulls = allowNulls;
    }
}

private size_t regionIndex(Cache[] caches, string name)
{
    foreach (index, cache; caches)
        if (cache.getName() == name)
            return index;
    return caches.length;
}
