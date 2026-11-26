/++
Flint tests for `Cookie`'s `Secure` and `HttpOnly` flags. Jakarta reads a flag as `"".equals(getAttribute(name))`, so
a cookie that never had the attribute is neither secure nor HTTP-only. In D an absent attribute's `null` compares
equal to `""`, and the first port read every fresh cookie as both.
+/
module flint.jakarta.servlet.cookie_flag_tests;

import flint.jakarta.servlet.http : Cookie;

@safe:

@("Cookie: a fresh cookie is neither secure nor HTTP-only")
unittest
{
    auto cookie = new Cookie("session", "abc");
    assert(!cookie.getSecure());
    assert(!cookie.isHttpOnly());
    assert(cookie.getAttribute("Secure") is null);
}

@("Cookie: setSecure and setHttpOnly set and clear the flags")
unittest
{
    auto cookie = new Cookie("session", "abc");
    cookie.setSecure(true);
    cookie.setHttpOnly(true);
    assert(cookie.getSecure());
    assert(cookie.isHttpOnly());
    cookie.setSecure(false);
    assert(!cookie.getSecure());
    assert(cookie.isHttpOnly());
    cookie.setHttpOnly(false);
    assert(!cookie.isHttpOnly());
    assert(cookie.getAttributes().length == 0);
}

@("Cookie: a present empty attribute sets the flag, whatever its case")
unittest
{
    auto cookie = new Cookie("session", "abc");
    cookie.setAttribute("secure", "Secure"[0 .. 0]);
    cookie.setAttribute("HTTPONLY", "");
    assert(cookie.getSecure());
    assert(cookie.isHttpOnly());
}

@("Cookie: a flag attribute with a value is not set, as in Jakarta")
unittest
{
    auto cookie = new Cookie("session", "abc");
    cookie.setAttribute("Secure", "yes");
    cookie.setAttribute("HttpOnly", "false");
    assert(!cookie.getSecure());
    assert(!cookie.isHttpOnly());
}
