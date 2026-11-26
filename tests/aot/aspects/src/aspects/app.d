module aspects.app;

import flint.aspectj.lang.annotation : Aspect, Before;
import flint.boot.autoconfigure : FlintBootApplication;
import flint.core.annotation : Order;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor;
import flint.engine.aot.proxy : Advisor, Invocation, Proceed;
import flint.stereotype : Component;
import flint.transaction.annotation : Transactional;

@safe:

/// Entry point metadata for the AOT fixture.
@FlintBootApplication
class Application
{
}

/// Shared call log for the target and advisors.
@Component
class Journal
{
    /// Events in execution order.
    string[] events;

    /// Records an event from one call.
    void add(string event)
    {
        events ~= event;
    }
}

/// Target bean with advised and unmatched operations.
@Component
class OwnerService
{
    private Journal journal;

    /// Shares the fixture journal.
    this(Journal journal)
    {
        this.journal = journal;
    }

    /// Exercises the common transaction and aspect chain.
    @Transactional
    int update(int value)
    {
        journal.add("update");
        return value + 1;
    }

    /// An aspect-only target method.
    void rename()
    {
        journal.add("rename");
    }

    /// Calls the aspect-only method on the target itself.
    void renameFromInside()
    {
        rename();
    }

    /// A method for which no registered aspect applies.
    void read()
    {
        journal.add("read");
    }
}

/// The unordered aspect ties the transaction advisor.
@Component
@Aspect
class Audit
{
    private Journal journal;
    private OwnerService service;

    /// An aspect can inject the service being proxied.
    this(Journal journal, OwnerService service)
    {
        this.journal = journal;
        this.service = service;
    }

    /// Advice for the selected method.
    @Before("execution(* aspects.app.OwnerService.update(..))")
    void beforeUpdate()
    {
        assert(service !is null);
        journal.add("before-update");
    }

    /// Advice for the selected method.
    @Before("execution(* aspects.app.OwnerService.rename(..))")
    void beforeRename()
    {
        journal.add("before-rename");
    }
}

/// An aspect declaration without a bean registration.
@Aspect
class UnregisteredAspect
{
    /// Advice for the selected method.
    @Before("execution(* aspects.app.OwnerService.read(..))")
    void beforeRead()
    {
        assert(false, "the aspect has no component registration");
    }
}

/// The explicit order puts this aspect before the transaction advisor.
@Component
@Aspect
@Order(-10)
class OrderedAudit
{
    private Journal journal;

    /// Shares the fixture journal.
    this(Journal journal)
    {
        this.journal = journal;
    }

    /// Advice for the selected method.
    @Before("execution(* aspects.app.OwnerService.update(..))")
    void beforeUpdate()
    {
        journal.add("ordered-before-update");
    }
}

/// A transaction boundary with the production advisor's default order and annotation selection.
@Component
class TransactionBoundary : Advisor
{
    private Journal journal;

    /// Shares the fixture journal.
    this(Journal journal)
    {
        this.journal = journal;
    }

    /// Selects methods with transaction metadata.
    bool appliesTo(const Descriptor, const(MethodDescriptor)* method)
    {
        foreach (ref annotation; method.annotations)
            if (annotation.type == "flint.transaction.annotation.Transactional")
                return true;
        return false;
    }

    int getOrder()
    {
        return int.max;
    }

    /// Records the boundary around the remainder of the chain.
    void invoke(ref Invocation invocation, scope Proceed proceed)
    {
        journal.add("transaction-start");
        proceed(invocation);
        journal.add("transaction-end");
    }
}
