module flint.java.test.uri_percent;

import flint.java.lang : IllegalArgumentException;
import flint.java.net : URI;

@safe:

@("URI.create validates escapes and preserves the supplied URI spelling")
unittest
{
    foreach (input; [
        "/p%2f", "/日本%20語", "?query=foo%25x", "/path#%09", "mailto:user%40example.org"
    ])
        assert(URI.create(input).toString() == input);
    foreach (input; ["/p%th", "/p%", "/p%1", "?query=foo%%x", "/path#%", "opaque:invalid%z0"])
        assert(rejects(input));
}

@("URI.create accepts an IPv6 scope only inside a bracketed authority")
unittest
{
    foreach (input; [
        "http://[fe80::1%eth0]/", "//us%65r@[::%eth0]/a%2f",
        "//[::ffff:192.0.2.1%nic_0.2]:90/a?qu%65ry#f%61g"
    ])
        assert(URI.create(input).toString() == input);
    foreach (input; [
        "/p/[::%eth0]", "?x=[::%eth0]", "//[not_ipv6%20]/", "//[::%25en%30]/", "//[::%e-th0]/",
        "//[::%eth0]:%61", "http://[fe80::1%eth0]/?a=%%x"
    ])
        assert(rejects(input));
}

private bool rejects(string input) pure
{
    try
        URI.create(input);
    catch (IllegalArgumentException)
        return true;
    return false;
}

@("URI.create reports malformed escape positions in UTF-16 units")
unittest
{
    assert(failureMessage("/p%th") == "Malformed escape pair at index 2: /p%th");
    assert(failureMessage("?query=foo%%x") == "Malformed escape pair at index 10: ?query=foo%%x");
    assert(failureMessage("/😀%2G") == "Malformed escape pair at index 3: /😀%2G");
    assert(failureMessage("//[::%eth0]?x=/p%GG") == "Malformed escape pair at index 16: //[::%eth0]?x=/p%GG");
    assert(failureMessage("//[::%25en%30]/") == "Illegal character in scope id at index 10: //[::%25en%30]/");
}

private string failureMessage(string input) pure
{
    try
        URI.create(input);
    catch (IllegalArgumentException failure)
        return failure.getMessage();
    assert(false, "Expected an invalid URI");
}
