/++
Flint's tests of the by-type name cache (Spring's `allBeanNamesByType`): kept once the configuration is frozen,
cleared by any registration, and safe for many threads at once (playbook R-4, R-7).
+/
module flint.beans.by_type_cache_test;

import flint.beans.factory.support : DefaultListableBeanFactory;
import flint.engine.aot.name : typeNameOf;

private interface Repository
{
}

private interface Service
{
}

private final class OwnerRepository : Repository
{
}

private final class PetRepository : Repository
{
}

private final class ClinicService : Service
{
}

@safe unittest
{
    auto factory = new DefaultListableBeanFactory;
    factory.registerSingleton("owners", new OwnerRepository);
    factory.registerSingleton("clinic", new ClinicService);
    // Before freezing: computed each time.
    assert(factory.getBeanNamesForTypeErased(typeNameOf!Repository) == ["owners"]);
    factory.freezeConfiguration();
    // Frozen: the cached answer, the same each time; callers get their own copy.
    auto first = factory.getBeanNamesForTypeErased(typeNameOf!Repository);
    first[0] = "changed by the caller";
    assert(factory.getBeanNamesForTypeErased(typeNameOf!Repository) == ["owners"]);
    assert(factory.getBeanNamesForTypeErased(typeNameOf!Service) == ["clinic"]);
    assert(factory.getBeanNamesForTypeErased("no.such.Type").length == 0);
    // A registration clears the cache, so the next lookup sees the new bean.
    factory.registerSingleton("pets", new PetRepository);
    assert(factory.getBeanNamesForTypeErased(typeNameOf!Repository) == ["owners", "pets"]);
    assert(cast(Object) factory.getBean!Service() is factory.getBean("clinic"));
}

unittest
{
    import core.thread : Thread;

    // Many threads resolving by type at once after the freeze: every answer stays right.
    auto factory = new DefaultListableBeanFactory;
    factory.registerSingleton("owners", new OwnerRepository);
    factory.registerSingleton("pets", new PetRepository);
    factory.registerSingleton("clinic", new ClinicService);
    factory.freezeConfiguration();
    shared bool failed;
    Thread[] threads;
    foreach (t; 0 .. 8)
        threads ~= new Thread({
            foreach (i; 0 .. 2_000)
            {
                const repositories = factory.getBeanNamesForTypeErased(typeNameOf!Repository);
                const services = factory.getBeanNamesForTypeErased(typeNameOf!Service);
                const missing = factory.getBeanNamesForTypeErased("app.Missing" ~ cast(char)('0' + i % 10));
                if (repositories != ["owners", "pets"] || services != ["clinic"] || missing.length != 0)
                    failed = true;
            }
        }).start();
    foreach (thread; threads)
        thread.join();
    assert(!failed);
}
