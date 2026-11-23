/// Transactional advice through the type hierarchy: the first aggregate with a match wins (Spring's
/// MergedAnnotationFinder), so a subclass's composed annotation beats its superclass's direct `@Transactional`.
module hier.service;

import flint.stereotype : Service;
import flint.transaction.annotation : Transactional;

@safe:

/// A composed annotation: `@Transactional` one level up.
@Transactional(value: "readOnlyManager", readOnly: true) struct ReadOnlyTransaction
{
}

/// Declares `@Transactional` directly.
@Transactional("baseManager") abstract class BaseService
{
}

/// Its own meta-annotated `@Transactional` (distance 1) wins over the superclass's direct one (distance 0).
@Service @ReadOnlyTransaction class ReportService : BaseService
{
    /// Advised as read-only, with the composed annotation's transaction manager.
    void run()
    {
    }
}
