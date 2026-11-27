module flint.java.net.formcharset_test;

import flint.java.net.internal.formdecode : decodeForm;
import flint.java.net.internal.formencode : encodeForm;
import flint.java.nio.charset : StandardCharsets;

@safe:

@("form charset encoding replaces unmappable values and respects unsafe UTF-16 runs")
unittest
{
    assert(encodeForm("café 😀", StandardCharsets.ISO_8859_1) == "caf%E9+%3F");
    assert(encodeForm("é😀", StandardCharsets.US_ASCII) == "%3F%3F");
    assert(encodeForm("!A!", StandardCharsets.UTF_16) == "%FE%FF%00%21A%FE%FF%00%21");
    assert(encodeForm("😀=", StandardCharsets.UTF_16BE) == "%D8%3D%DE%00%00%3D");
    assert(encodeForm("é+", StandardCharsets.UTF_16LE) == "%E9%00%2B%00");
}

@("form charset decoding distinguishes BOM presence from explicit byte order")
unittest
{
    assert(decodeForm("%FE%FF%00%41X%FF%FE%42%00", StandardCharsets.UTF_16) == "AXB");
    assert(decodeForm("%FE%FF%00%41", StandardCharsets.UTF_16BE) == "\uFEFFA");
    assert(decodeForm("%FF%FE%41%00", StandardCharsets.UTF_16LE) == "\uFEFFA");
    assert(decodeForm("%FF%FE%41%00", StandardCharsets.UTF_16BE) == "\uFFFE\u4100");
    assert(decodeForm("%D8%00%00%41%00%42", StandardCharsets.UTF_16BE) == "�B");
    assert(decodeForm("%D8%00%00", StandardCharsets.UTF_16BE) == "�");
    assert(decodeForm("%FF%41", StandardCharsets.US_ASCII) == "�A");
    assert(decodeForm("%ＦＦ%٤١", StandardCharsets.ISO_8859_1) == "ÿA");
}
