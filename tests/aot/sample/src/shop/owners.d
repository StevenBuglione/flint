/// Components with constructor injection, lifecycle callbacks and advice.
module shop.owners;

import flint.beans.factory : DisposableBean;
import flint.cache.annotation : Cacheable;
import flint.jakarta.annotation : PostConstruct, PreDestroy;
import flint.scheduling.annotation : Async;
import flint.stereotype : Repository, Service;
import flint.transaction.annotation : Transactional;

@safe:

/// Owner names by id.
@Repository class OwnerStore : DisposableBean
{
    /// Lifecycle events, in order.
    string[] events;

    /// The owner's name.
    string find(long id)
    {
        return id == 1 ? "Ada" : "Grace";
    }

    /// Records the destroy callback.
    override void destroy()
    {
        events ~= "store destroyed";
    }
}

/// Owner use cases; advised by the transaction and cache interceptors.
@Service class OwnerService
{
    private OwnerStore store;
    /// Calls that reached the target.
    int calls;
    /// Whether @PostConstruct ran.
    bool ready;

    /// Constructor injection.
    this(OwnerStore store)
    {
        this.store = store;
    }

    /// Runs after injection.
    @PostConstruct void start()
    {
        ready = true;
    }

    /// Runs at shutdown.
    @PreDestroy void stop()
    {
        store.events ~= "service stopped";
    }

    /// Advised: read-only transaction and the "owners" cache.
    @Transactional(readOnly: true) @Cacheable("owners") string findName(long id)
    {
        calls++;
        return store.find(id);
    }

    /// Whether @PostConstruct ran; read through a method, since a proxy's own fields are never initialized.
    bool isReady()
    {
        return ready;
    }

    /// Calls that reached the target.
    int callCount()
    {
        return calls;
    }

    /// Calls `findName` on itself: Spring runs no advice for self-invocation.
    string describe(long id)
    {
        return "owner " ~ findName(id);
    }

    /// Fire-and-forget notification.
    @Async void notifyOwner(long id)
    {
        calls += 100;
    }
}
