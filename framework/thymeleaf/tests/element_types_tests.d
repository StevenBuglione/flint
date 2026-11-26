/// Behavioral checks for Thymeleaf 3.1.7.RELEASE element and attribute classifications.
module flint.thymeleaf.element_types_tests;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.thymeleaf.engine : HTMLElementType;
import flint.thymeleaf.model : AttributeValueQuotes;

@safe:

@("HTML element types preserve names, ordering and void classification") unittest
{
    auto values = HTMLElementType.values();
    assert(values == [
        HTMLElementType.VOID, HTMLElementType.RAW_TEXT, HTMLElementType.ESCAPABLE_RAW_TEXT,
        HTMLElementType.FOREIGN, HTMLElementType.NORMAL
    ]);
    foreach (index, type; values)
    {
        assert(type.ordinal() == index);
        assert(type.isVoid() == (type == HTMLElementType.VOID));
        assert(type.toString() == type.name());
        assert(HTMLElementType.valueOf(type.name()) == type);
    }
    values[0] = HTMLElementType.NORMAL;
    assert(HTMLElementType.values()[0] == HTMLElementType.VOID);
}

@("HTML element type lookup uses the exact declared name") unittest
{
    foreach (name; ["", "raw_text", " NORMAL", "VOID "])
    {
        try
        {
            HTMLElementType.valueOf(name);
            assert(0, "expected the invalid name to be rejected");
        }
        catch (IllegalArgumentException error)
        {
            assert(error.msg == "No enum constant org.thymeleaf.engine.HTMLElementType." ~ name);
        }
    }
    try
    {
        HTMLElementType.valueOf(null);
        assert(0, "expected the null name to be rejected");
    }
    catch (NullPointerException error)
    {
        assert(error.msg == "Name is null");
    }
}

@("attribute quote constants keep declaration order") unittest
{
    assert(cast(int) AttributeValueQuotes.DOUBLE == 0);
    assert(cast(int) AttributeValueQuotes.SINGLE == 1);
    assert(cast(int) AttributeValueQuotes.NONE == 2);
}
