/++
Flint tests for `Cookie`'s `Max-Age`, which Jakarta reads with `Integer.parseInt` and writes with `String.valueOf`.
+/
module flint.jakarta.servlet.cookie_max_age_tests;

import flint.jakarta.servlet.http : Cookie;
import flint.java.lang : NumberFormatException;

@safe:

@("Cookie: Max-Age is -1 until set, and a negative expiry removes it")
unittest
{
    auto cookie = new Cookie("session", "abc");
    assert(cookie.getMaxAge() == -1);
    cookie.setMaxAge(0);
    assert(cookie.getAttribute("Max-Age") == "0" && cookie.getMaxAge() == 0);
    cookie.setMaxAge(int.max);
    assert(cookie.getAttribute("Max-Age") == "2147483647" && cookie.getMaxAge() == int.max);
    cookie.setMaxAge(-1);
    assert(cookie.getAttribute("Max-Age") is null && cookie.getMaxAge() == -1);
}

@("Cookie: Max-Age reads a signed decimal int, as Integer.parseInt does")
unittest
{
    auto cookie = new Cookie("session", "abc");
    cookie.setAttribute("Max-Age", "+3600");
    assert(cookie.getMaxAge() == 3600);
    cookie.setAttribute("Max-Age", "-2147483648");
    assert(cookie.getMaxAge() == int.min);
}

@("Cookie: a Max-Age that is not a decimal int throws NumberFormatException")
unittest
{
    auto cookie = new Cookie("session", "abc");
    foreach (text; ["", "1h", " 60", "0x10", "2147483648", "-2147483649", "-"])
    {
        cookie.setAttribute("Max-Age", text.length == 0 ? "60"[0 .. 0] : text);
        bool thrown;
        try
            cast(void) cookie.getMaxAge();
        catch (NumberFormatException e)
        {
            thrown = true;
            assert(e.msg == "For input string: \"" ~ text ~ "\"", e.msg);
        }
        assert(thrown, text);
    }
}
