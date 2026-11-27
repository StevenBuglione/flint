// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.passwordauthentication_test;

import flint.java.net.passwordauthentication : PasswordAuthentication;

@safe:

// Rows from pinned Temurin 21.0.13+9 (PasswordAuthenticationOracle.java): key, tab, value. Every row is computed
// below the same way; the null-password row differs by R26 and is checked separately.
private static immutable string expected = import("passwordauthentication/temurin.tsv");

private string hex(uint value) pure nothrow
{
    enum digits = "0123456789abcdef";
    string text;
    do
    {
        text = digits[value & 0xF] ~ text;
        value >>= 4;
    }
    while (value != 0);
    return text;
}

private string decimal(size_t value) pure nothrow
{
    string text;
    do
    {
        text = cast(char)('0' + value % 10) ~ text;
        value /= 10;
    }
    while (value != 0);
    return text;
}

private string narrow(const(wchar)[] units) pure nothrow
{
    string text;
    foreach (unit; units)
        text ~= cast(char) unit;
    return text;
}

private string flag(bool value) pure nothrow @nogc
{
    return value ? "true" : "false";
}

private string observed() pure nothrow
{
    string rows;
    void row(string key, string value)
    {
        rows ~= key ~ "\t" ~ value ~ "\n";
    }

    wchar[] secret = "secret"w.dup;
    auto a = new PasswordAuthentication("alice", secret);
    secret[0] = 'S';
    row("user", a.getUserName());
    row("password", narrow(a.getPassword()));
    row("copied-not-shared", flag(a.getPassword() !is secret));
    row("same-array-each-call", flag(a.getPassword() is a.getPassword()));
    a.getPassword()[0] = 'X';
    row("write-through-returned-array", narrow(a.getPassword()));
    auto b = new PasswordAuthentication("alice", "secret"w);
    auto c = new PasswordAuthentication("alice", "secret"w);
    row("equal-data-equals", flag(b is c));
    row("self-equals", flag(b is b));
    row("empty-user", "[" ~ new PasswordAuthentication("", null).getUserName() ~ "]");
    row("empty-password-length", decimal(new PasswordAuthentication("u", []).getPassword().length));
    auto d = new PasswordAuthentication("u", "p\U0001F600w"w);
    row("utf16-units", decimal(d.getPassword().length));
    row("utf16-unit-1", hex(d.getPassword()[1]));
    const wchar[] lone = [cast(wchar) 0xD800];
    row("lone-surrogate-kept", hex(new PasswordAuthentication("u", lone).getPassword()[0]));
    return rows;
}

unittest
{
    enum nullRow = "null-password\tNullPointerException\n";
    assert(expected.length > nullRow.length && expected[$ - nullRow.length .. $] == nullRow);
    assert(observed() == expected[0 .. $ - nullRow.length]);
}

unittest
{
    // R26: a null password counts as empty where Java throws NullPointerException.
    auto auth = new PasswordAuthentication("u", null);
    assert(auth.getPassword().length == 0 && auth.getUserName() == "u");
}

unittest
{
    // Identity, as in Java, which doesn't override equals or hashCode: equal data is still two objects.
    auto a = new PasswordAuthentication("alice", "pw"w);
    auto b = new PasswordAuthentication("alice", "pw"w);
    assert(a !is b && a.getPassword() == b.getPassword() && a.getPassword() !is b.getPassword());
}
