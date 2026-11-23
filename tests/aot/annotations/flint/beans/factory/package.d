/// Fixture for Flint AOT tests: `org.springframework.beans.factory`.
module flint.beans.factory;

@safe:

/// `InitializingBean`.
interface InitializingBean
{
    /// Called after injection.
    void afterPropertiesSet();
}

/// `DisposableBean`.
interface DisposableBean
{
    /// Called at shutdown.
    void destroy();
}
