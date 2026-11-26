/// Behavioral checks for Thymeleaf 3.1.7.RELEASE TemplateMode.java.
module flint.thymeleaf.template_mode_tests;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.thymeleaf.templatemode : TemplateMode;

@safe:

@("Thymeleaf mode properties match the upstream enum") unittest
{
    const modes = TemplateMode.values();
    assert(modes == [
        TemplateMode.HTML, TemplateMode.XML, TemplateMode.TEXT, TemplateMode.JAVASCRIPT,
        TemplateMode.CSS, TemplateMode.RAW
    ]);
    foreach (index, mode; modes)
    {
        assert(mode.ordinal() == index);
        assert(mode.isMarkup() == (index < 2));
        assert(mode.isText() == (index >= 2 && index <= 4));
        assert(mode.isCaseSensitive() == (index != 0));
        assert(mode.name() == mode.toString());
        assert(TemplateMode.valueOf(mode.name()) == mode);
    }
}

@("values returns a fresh array and valueOf resolves exact names") unittest
{
    auto values = TemplateMode.values();
    values[0] = TemplateMode.RAW;
    assert(TemplateMode.values()[0] == TemplateMode.HTML);
    foreach (name; ["", "html", " HTML", "UNSUPPORTED"])
    {
        try
        {
            TemplateMode.valueOf(name);
            assert(0, "expected the invalid name to be rejected");
        }
        catch (IllegalArgumentException error)
        {
            assert(error.msg == "No enum constant org.thymeleaf.templatemode.TemplateMode." ~ name);
        }
    }
    try
    {
        TemplateMode.valueOf(null);
        assert(0, "expected the missing name to be rejected");
    }
    catch (NullPointerException error)
    {
        assert(error.msg == "Name is null");
    }
}
