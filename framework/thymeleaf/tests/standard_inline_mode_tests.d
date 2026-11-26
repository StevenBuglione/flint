/// Behavioral checks for Thymeleaf 3.1.7.RELEASE StandardInlineMode.java.
module flint.thymeleaf.standard_inline_mode_tests;

import flint.java.lang : IllegalArgumentException;
import flint.thymeleaf.standard.inline : StandardInlineMode, parse;

@safe:

@("inline modes preserve declaration order and Java case matching") unittest
{
    assert(parse("none") == StandardInlineMode.NONE);
    assert(parse("Html") == StandardInlineMode.HTML);
    assert(parse("XmL") == StandardInlineMode.XML);
    assert(parse("TEXT") == StandardInlineMode.TEXT);
    assert(parse("jAvAsCrIpT") == StandardInlineMode.JAVASCRIPT);
    assert(parse("csS") == StandardInlineMode.CSS);

    // Java folds dotted I, dotless I and long S when comparing with these ASCII names.
    assert(parse("javaſcrİpt") == StandardInlineMode.JAVASCRIPT);
    assert(parse("JAVASCRıPT") == StandardInlineMode.JAVASCRIPT);
    assert(parse("cſſ") == StandardInlineMode.CSS);

    assert(StandardInlineMode.NONE == 0);
    assert(StandardInlineMode.HTML == 1);
    assert(StandardInlineMode.XML == 2);
    assert(StandardInlineMode.TEXT == 3);
    assert(StandardInlineMode.JAVASCRIPT == 4);
    assert(StandardInlineMode.CSS == 5);
}

@("inline mode rejection keeps the original value in the diagnostic") unittest
{
    foreach (input; [null, "", " \t\n", "\x00\x1f"])
        assertRejection(input, "Inline mode cannot be null or empty");
    foreach (input; [
        "HTML ", " HTML", "\tcss", "RAW", "NÖNE", "JAVASCRIPTZ", "\u00a0", "\xc4", "CSS\x00"
    ])
        assertRejection(input, "Unrecognized inline mode: " ~ input);
}

private void assertRejection(string input, string message)
{
    try
    {
        parse(input);
        assert(0, "expected invalid inline mode to throw");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == message);
    }
}
