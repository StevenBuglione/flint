/// Checks the pinned Thymeleaf StringUtils.isEmpty contract.
module flint.thymeleaf.string_utils_tests;

import flint.thymeleaf.util : StringUtils;

@safe:

@("StringUtils.isEmpty accepts null and empty strings without allocating") unittest
{
    static void check() pure nothrow @nogc
    {
        string missing;
        assert(StringUtils.isEmpty(missing));
        assert(StringUtils.isEmpty(""));
        string text = "prefix";
        assert(StringUtils.isEmpty(text[3 .. 3]));
        assert(!StringUtils.isEmpty(" "));
        assert(!StringUtils.isEmpty("\t\n"));
        assert(!StringUtils.isEmpty("\0"));
        assert(!StringUtils.isEmpty("\u2003"));
        assert(!StringUtils.isEmpty("😀"));
    }

    check();
}
