module flint.bean_exception_contract_test;

import flint.beans : FatalBeanException;
import flint.beans.factory : BeanCreationException, BeanCreationNotAllowedException,
    BeanInitializationException, BeanIsAbstractException, FactoryBeanNotInitializedException;
import flint.beans.factory.support : BeanDefinitionValidationException;
import flint.java.lang : IllegalArgumentException;

@safe:

@("bean creation exception subtypes preserve the bean name and detail")
unittest
{
    BeanCreationException denied = new BeanCreationNotAllowedException("worker", "Shutting down");
    assert(denied.getBeanName() == "worker" && denied.getCause() is null);
    assert(denied.getMessage() == "Error creating bean with name 'worker': Shutting down");

    BeanCreationException abstractBean = new BeanIsAbstractException("parent");
    assert(abstractBean.getBeanName() == "parent" && abstractBean.getCause() is null);
    assert(abstractBean.getMessage() == "Error creating bean with name 'parent': Bean definition is abstract");
}

@("bean initialization and definition validation exceptions retain the supplied cause")
unittest
{
    auto cause = new IllegalArgumentException("Invalid key");
    FatalBeanException initialization = new BeanInitializationException("Setup failed", cause);
    assert(initialization.getMessage() == "Setup failed" && initialization.getCause() is cause);
    assert((new BeanInitializationException("Setup failed")).getCause() is null);

    FatalBeanException validation = new BeanDefinitionValidationException("Invalid definition", cause);
    assert(validation.getMessage() == "Invalid definition" && validation.getCause() is cause);
    assert((new BeanDefinitionValidationException("Invalid definition")).getCause() is null);
}

@("uninitialized FactoryBean has a default and an explicit message")
unittest
{
    FatalBeanException notReady = new FactoryBeanNotInitializedException;
    assert(notReady.getMessage() == "FactoryBean is not fully initialized yet");
    assert(notReady.getCause() is null);
    assert((new FactoryBeanNotInitializedException("Waiting for properties")).getMessage() == "Waiting for properties");
}

@("message-only bean exceptions leave the cause uninitialized, so initCause still works")
unittest
{
    import flint.beans : FatalBeanException;
    import flint.beans.factory : BeanCreationException, BeanCreationNotAllowedException,
        BeanDefinitionStoreException, BeanIsAbstractException;
    import flint.core : NestedRuntimeException;
    import flint.java.lang : IllegalStateException;

    // Java's (String) constructors leave the cause uninitialized; a later initCause sets it once.
    auto cause = new Exception("root");
    NestedRuntimeException[] messageOnly = [
        new FatalBeanException("fatal"), new BeanCreationException("create"),
        new BeanCreationException("bean", "detail"),
        new BeanCreationNotAllowedException("bean", "closing"),
        new BeanIsAbstractException("bean"), new BeanDefinitionStoreException("store")
    ];
    foreach (failure; messageOnly)
    {
        assert(failure.getCause() is null);
        assert(failure.initCause(cause) is failure && failure.getCause() is cause);
    }

    // A supplied cause is initialized, so initCause rejects a second one.
    auto withCause = new FatalBeanException("fatal", cause);
    assert(withCause.getCause() is cause);
    bool rejected;
    try
        withCause.initCause(new Exception("other"));
    catch (IllegalStateException)
        rejected = true;
    assert(rejected);

    // A `null` literal selects the cause overload (Java's (String, Throwable)), which still reports no cause.
    assert((new FatalBeanException("fatal", null)).getCause() is null);
    assert((new BeanCreationException("bean", "detail", null)).getCause() is null);
}
