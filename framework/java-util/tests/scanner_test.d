/*
 * Copyright Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
module scanner_test;

import flint.java.lang : IllegalStateException, NullPointerException, UnsupportedOperationException;
import flint.java.util : NoSuchElementException;
import flint.java.util.scanner : Scanner;
import std.exception : assertThrown;

@safe:

private string[] drain(Scanner scanner)
{
    string[] tokens;
    while (scanner.hasNext())
        tokens ~= scanner.next();
    return tokens;
}

private string[] drainLines(Scanner scanner)
{
    string[] lines;
    while (scanner.hasNextLine())
        lines ~= scanner.nextLine();
    return lines;
}

@("Scanner splits on the Java whitespace set and excludes nonbreaking spaces") unittest
{
    assert(new Scanner("").hasNext() == false);
    assert(new Scanner("   \t\n\r\f").hasNext() == false);
    assert(drain(new Scanner("  a\tb\nc\r\nd  ")) == ["a", "b", "c", "d"]);
    assert(drain(new Scanner("a\u000Bb")) == ["a", "b"]);
    assert(drain(new Scanner("a\u001Cb\u001Dc\u001Ed\u001Fe")) == ["a", "b", "c", "d", "e"]);
    assert(drain(new Scanner("a\u1680b")) == ["a", "b"]);
    assert(drain(new Scanner("a\u2000b\u2001c\u2002d\u2003e\u2004f\u2005g\u2006h\u2009i\u200Aj")) == [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j"
    ]);
    assert(drain(new Scanner("a\u2007b\u00A0c\u200Bd")) == ["a\u2007b\u00A0c\u200Bd"]);
    assert(drain(new Scanner("a\u2028b\u2029c\u205Fd\u3000e")) == ["a", "b", "c", "d", "e"]);
    assert(new Scanner("   ").hasNext() == false);
    assert(drain(new Scanner("x")) == ["x"]);
}

@("Scanner next throws NoSuchElementException at the end") unittest
{
    auto scanner = new Scanner("a");
    assert(scanner.next() == "a");
    assert(scanner.hasNext() == false);
    assertThrown!NoSuchElementException(scanner.next());
}

@("Scanner nextLine returns the rest of the line including leading whitespace") unittest
{
    assert(drainLines(new Scanner("")).length == 0);
    assert(drainLines(new Scanner("\n")) == [""]);
    assert(drainLines(new Scanner("a\nb")) == ["a", "b"]);
    assert(drainLines(new Scanner("a\n")) == ["a"]);
    assert(drainLines(new Scanner("a\r\nb\r\n")) == ["a", "b"]);
    assert(drainLines(new Scanner("a\rb")) == ["a", "b"]);

    auto scanner = new Scanner("a b\nc d\n");
    assert(scanner.hasNext() == true);
    assert(scanner.next() == "a");
    assert(scanner.hasNextLine() == true);
    assert(scanner.nextLine() == " b");
    assert(scanner.hasNext() == true);
    assert(scanner.next() == "c");
    assert(scanner.next() == "d");
    assert(scanner.hasNextLine() == true);
    assert(scanner.nextLine() == "");
    assert(scanner.hasNext() == false);
    assert(scanner.hasNextLine() == false);
}

@("Scanner mixes token and line reads on whitespace-only input") unittest
{
    auto scanner = new Scanner("  \n  x");
    assert(scanner.hasNext() == true);
    assert(scanner.next() == "x");
    assert(scanner.hasNextLine() == false);
    assert(scanner.hasNext() == false);
    assert(scanner.hasNextLine() == false);

    auto spaces = new Scanner("   ");
    assert(spaces.hasNext() == false);
    assert(spaces.hasNextLine() == true);
    assert(spaces.nextLine() == "   ");
    assert(spaces.hasNext() == false);
    assert(spaces.hasNextLine() == false);
}

@("Scanner close rejects later scanning and ioException stays null") unittest
{
    auto scanner = new Scanner("a b");
    assert(scanner.hasNext() == true);
    scanner.close();
    assertThrown!IllegalStateException(scanner.hasNext());
    assertThrown!IllegalStateException(scanner.next());
    assertThrown!IllegalStateException(scanner.nextLine());
    assertThrown!IllegalStateException(scanner.hasNextLine());
    assert(scanner.ioException() is null);
}

@("Scanner rejects a null source and an unsupported Iterator.remove") unittest
{
    string none;
    assertThrown!NullPointerException(new Scanner(none));
    auto scanner = new Scanner("a b");
    scanner.next();
    assertThrown!UnsupportedOperationException(scanner.remove());
}
