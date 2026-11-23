/// Fixture for Flint AOT tests: `org.springframework.transaction.annotation`.
module flint.transaction.annotation;

import flint.core.annotation : AliasFor;

@safe:

/// Transaction propagation.
enum Propagation
{
    REQUIRED,
    SUPPORTS,
    MANDATORY,
    REQUIRES_NEW,
    NOT_SUPPORTED,
    NEVER,
    NESTED
}

/// `@Transactional`.
struct Transactional
{
    /// Alias of `transactionManager`.
    @AliasFor("transactionManager") string value;
    /// Transaction manager bean.
    @AliasFor("value") string transactionManager;
    /// Propagation.
    Propagation propagation;
    /// Read-only hint.
    bool readOnly;
}
