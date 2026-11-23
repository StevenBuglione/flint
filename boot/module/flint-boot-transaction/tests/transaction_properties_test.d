/// Flint tests: `flint.transaction.*` defaults.
module transaction_properties_test;

import flint.boot.transaction.autoconfigure : TransactionProperties;

@safe:

unittest
{
    auto properties = new TransactionProperties;
    assert(properties.getDefaultTimeout().isEmpty());
    assert(properties.getRollbackOnCommitFailure().isEmpty());
}
