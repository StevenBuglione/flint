module number_point_type_tests;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.thymeleaf.util : NumberPointType;

@safe:

unittest
{
    alias Type = NumberPointType;
    const expected = [Type.POINT, Type.COMMA, Type.WHITESPACE, Type.NONE, Type.DEFAULT];
    const names = ["POINT", "COMMA", "WHITESPACE", "NONE", "DEFAULT"];
    auto values = Type.values();
    assert(values == expected);
    foreach (index, value; values)
    {
        const name = names[index];
        assert(value.ordinal() == index);
        assert(value.name() == name && value.getName() == name && value.toString() == name);
        assert(Type.valueOf(name) == value);
        assert(Type.match(name).get == value);
    }

    values[0] = Type.DEFAULT;
    assert(Type.values() == expected);
}

unittest
{
    alias Type = NumberPointType;
    assert(Type.match(null).isNull);
    foreach (invalid; ["", "comma", "COMMA ", " COMMA", "POİNT", "NONE\0", "NEW"])
    {
        assert(Type.match(invalid).isNull);
        try
        {
            Type.valueOf(invalid);
            assert(false, "expected IllegalArgumentException");
        }
        catch (IllegalArgumentException error)
        {
            assert(error.msg == "No enum constant org.thymeleaf.util.NumberPointType." ~ invalid);
        }
    }
    try
    {
        Type.valueOf(null);
        assert(false, "expected NullPointerException");
    }
    catch (NullPointerException error)
    {
        assert(error.msg == "Name is null");
    }
}
