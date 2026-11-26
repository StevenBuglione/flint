module uuid_test;

import flint.java.util.uuid : UUID;

@safe:

@("Generated UUIDs use lowercase hex and the standard v4 layout")
unittest
{
    bool[string] seen;
    foreach (i; 0 .. 32)
    {
        auto value = UUID.randomUUID();
        assert(value.version_() == 4);
        assert(value.variant() == 2);
        const text = value.toString();
        assert(text.length == 36);
        foreach (position, ch; text)
        {
            if (position == 8 || position == 13 || position == 18 || position == 23)
                assert(ch == '-');
            else
                assert((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f'));
        }
        assert(text[14] == '4');
        assert(text[19] == '8' || text[19] == '9' || text[19] == 'a' || text[19] == 'b');
        assert((text in seen) is null);
        seen[text] = true;
    }
}
