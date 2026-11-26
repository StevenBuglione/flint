/// Behavioral checks for Thymeleaf 3.1.7.RELEASE IDialect and AbstractDialect.
module flint.thymeleaf.dialect_tests;

import flint.thymeleaf.dialect : AbstractDialect, IDialect;

@safe:

private final class TestDialect : AbstractDialect
{
    this(string name)
    {
        super(name);
    }
}

@("a dialect retains its original name through the interface") unittest
{
    const name = "  Résumé & Layout  ";
    IDialect dialect = new TestDialect(name);
    assert(dialect.getName() is name);
}

@("abstract dialect accepts empty and default-initialized names") unittest
{
    const string empty = "x"[0 .. 0];
    assert(empty !is null);
    IDialect emptyDialect = new TestDialect(empty);
    assert(emptyDialect.getName() is empty);
    assert(new TestDialect("").getName() == "");

    const string defaultName;
    assert(new TestDialect(defaultName).getName() == "");
}
