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

    @("File collapses duplicate separators and drops a trailing separator")
    unittest
    {
        const collapsed = new File("a//b");
        assert(collapsed.getPath() == "a/b");
        assert(collapsed.getName() == "b");
        assert(collapsed.getParent() == "a");

        const trailing = new File("x//y//");
        assert(trailing.getPath() == "x/y");
        assert(trailing.getName() == "y");
        assert(trailing.getParent() == "x");

        const rooted = new File("//a//b/");
        assert(rooted.getPath() == "/a/b");
        assert(rooted.getName() == "b");
        assert(rooted.getParent() == "/a");
        assert(rooted.toString() == "/a/b");
    }

    @("File keeps a root pathname and gives it neither a name nor a parent")
    unittest
    {
        foreach (const spelling; ["/", "//", "///"])
        {
            const root = new File(spelling);
            assert(root.getPath() == "/");
            assert(root.getName().length == 0);
            assert(root.getParent() is null);
            assert(root.toString() == "/");
        }
    }

    @("File keeps dot segments instead of resolving them")
    unittest
    {
        assert(new File("a/./b").getPath() == "a/./b");
        assert(new File("a/./b").getParent() == "a/.");
        assert(new File("a/../b").getPath() == "a/../b");
        assert(new File("./").getPath() == ".");
        assert(new File(".//").getPath() == ".");
    }

    @("File joins an empty parent with the platform default")
    unittest
    {
        const underRoot = new File("", "child");
        assert(underRoot.getPath() == "/child");
        assert(underRoot.getName() == "child");
        assert(underRoot.getParent() == "/");

        assert(new File("", "").getPath() == "/");
    }

    @("File keeps a null parent as a bare child")
    unittest
    {
        const bare = new File(cast(string) null, "child");
        assert(bare.getPath() == "child");
        assert(bare.getParent() is null);

        const fromFile = new File(cast(File) null, "child");
        assert(fromFile.getPath() == "child");
        assert(fromFile.getParent() is null);
    }

    @("File joins a child under an already normalized File parent")
    unittest
    {
        assert(new File(new File("a//b/"), "c//d").getPath() == "a/b/c/d");
        assert(new File(new File(""), "child").getPath() == "/child");
        assert(new File(new File("/p/"), "/child").getPath() == "/p/child");
        assert(new File(new File("/p"), "/").getPath() == "/p");
    }

    @("File normalizes both parent and child before joining them")
    unittest
    {
        assert(new File("/p/", "child").getPath() == "/p/child");
        assert(new File("/p/", "/child").getPath() == "/p/child");
        assert(new File("a//b", "c//d").getPath() == "a/b/c/d");
        assert(new File("/p", "").getPath() == "/p");
        assert(new File("/p", "").getParent() == "/");
    }

    @("File drops a separator the join added before a rooted child")
    unittest
    {
        assert(new File("a", "/").getPath() == "a");
        assert(new File("a/b", "//").getPath() == "a/b");
        assert(new File("/", "/").getPath() == "/");
        assert(new File("a//b", "//c//").getPath() == "a/b/c");
        assert(new File("a/b/../c", "d").getPath() == "a/b/../c/d");
    }

    @("File normalization keeps dot segments around a duplicate separator")
    unittest
    {
        assert(new File("a//..//b").getPath() == "a/../b");
        assert(new File("/a/../b/").getPath() == "/a/../b");
        assert(new File("/./").getPath() == "/.");
    }

    @("File resolves an empty pathname to the startup working directory")
    unittest
    {
        const working = new File("").getAbsolutePath();
        assert(working.length > 0 && working[0] == '/');
        assert(working[$ - 1] != '/');

        assert(new File("").getAbsolutePath() == working);
        assert(new File("a//b/").getAbsolutePath() == (working == "/" ? "/a/b" : working ~ "/a/b"));
        assert(new File("/x//y").getAbsolutePath() == "/x/y");
        assert(new File("/").getAbsolutePath() == "/");
    }
}
