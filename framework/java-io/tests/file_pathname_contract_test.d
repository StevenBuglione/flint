// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java abstract pathname facade. */
module flint.java.io.file_pathname_contract_test;

import flint.java.io : File;

@safe:

@("File exposes the name and absence of a parent for a bare relative pathname")
unittest
{
    const file = new File("é.txt");
    assert(file.getPath() == "é.txt");
    assert(file.getName() == "é.txt");
    assert(file.getParent() is null);
    assert(file.toString() == file.getPath());

    const empty = new File("");
    assert(empty.getPath().length == 0);
    assert(empty.getName().length == 0);
    assert(empty.getParent() is null);
}

version (Posix)
{
    @("File exposes components for a simple POSIX parent and child")
    unittest
    {
        const file = new File("/parent", "é.txt");
        assert(file.getPath() == "/parent/é.txt");
        assert(file.getName() == "é.txt");
        assert(file.getParent() == "/parent");
        assert(file.toString() == file.getPath());
    }
}
