module logging_utils_tests;

import flint.thymeleaf.util : LoggingUtils;
import std.typecons : Nullable;

@safe:

unittest
{
    alias logName = LoggingUtils.loggifyTemplateName;
    assert(logName(Nullable!string.init).isNull);
    const empty = logName(Nullable!string(""));
    assert(!empty.isNull && empty.get == "");
    assert(logName(Nullable!string("a\nb\r\nc\td")).get == "a b\r c\td");

    // These inputs have 120 and 121 UTF-16 units respectively, despite each being wider in UTF-8.
    enum multibyte = repeatForTest("😀é", 5);
    enum atLimit = multibyte ~ repeatForTest("a", 105);
    enum overLimit = atLimit ~ "\n";
    assert(logName(Nullable!string(atLimit)).get is atLimit);
    assert(logName(Nullable!string(overLimit)).get == multibyte ~ repeatForTest("a",
            20) ~ "[...]" ~ repeatForTest("a", 79) ~ " ");
}

unittest
{
    alias logName = LoggingUtils.loggifyTemplateName;
    enum prefix = repeatForTest("é", 33) ~ "\n";
    enum suffix = repeatForTest("中", 78) ~ "\n";
    enum middle = "discard this portion";
    enum input = prefix ~ "😀" ~ middle ~ "😀" ~ suffix;
    assert(logName(Nullable!string(input)).get == prefix[0 .. $ - 1] ~ " �[...]�" ~ suffix[0 .. $ - 1] ~ " ");

    enum complete = repeatForTest("a", 33) ~ "😀" ~ middle ~ "😀" ~ suffix;
    assert(logName(Nullable!string(complete)).get == repeatForTest("a", 33) ~ "😀[...]�" ~ suffix[0 .. $ - 1] ~ " ");
}

private string repeatForTest(string unit, size_t count)
{
    string result;
    foreach (_; 0 .. count)
        result ~= unit;
    return result;
}
