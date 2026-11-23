// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/properties/source/ConfigurationPropertyNameTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test.
module boot_tests.configuration_property_name_test;

import boot_tests.support : assertThrows;
import flint.boot.context.properties.source : ConfigurationPropertyName, InvalidConfigurationPropertyNameException;
import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException;

@safe:

private alias Name = ConfigurationPropertyName;
private alias Form = ConfigurationPropertyName.Form;

private void invalid(string name)
{
    assertThrows!InvalidConfigurationPropertyNameException(() { Name.of(name); }, "is not valid");
}

@("ofNameShouldNotBeNull") unittest
{
    assertThrows!IllegalArgumentException(() { Name.of(null); }, "'name' must not be null");
}

@("ofNameShouldNotStartWithDash") unittest
{
    invalid("-foo");
}

@("ofNameShouldNotStartWithDot") unittest
{
    invalid(".foo");
}

@("ofNameShouldNotEndWithDot") unittest
{
    invalid("foo.");
}

@("ofNameShouldNotContainUppercase") unittest
{
    invalid("fOo");
}

@("ofNameShouldNotContainInvalidChars") unittest
{
    foreach (char c; "_@$%*+=':;")
        invalid("foo" ~ c);
}

@("ofNameWhenSimple") unittest
{
    auto name = Name.of("name");
    assert(name.toString() == "name");
    assert(name.getNumberOfElements() == 1);
    assert(name.getElement(0, Form.ORIGINAL) == "name");
    assert(!name.isIndexed(0));
}

@("ofNameWhenStartsWithNumber") unittest
{
    auto name = Name.of("1foo");
    assert(name.toString() == "1foo");
    assert(name.getNumberOfElements() == 1);
    assert(name.getElement(0, Form.ORIGINAL) == "1foo");
    assert(!name.isIndexed(0));
}

@("ofNameWhenRunOnAssociative") unittest
{
    auto name = Name.of("foo[bar]");
    assert(name.toString() == "foo[bar]");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(1, Form.ORIGINAL) == "bar");
    assert(!name.isIndexed(0));
    assert(name.isIndexed(1));
}

@("ofNameWhenDotOnAssociative") unittest
{
    auto name = Name.of("foo.bar");
    assert(name.toString() == "foo.bar");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(1, Form.ORIGINAL) == "bar");
    assert(!name.isIndexed(0));
    assert(!name.isIndexed(1));
}

@("ofNameWhenDotAndAssociative") unittest
{
    auto name = Name.of("foo.[bar]");
    assert(name.toString() == "foo[bar]");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(1, Form.ORIGINAL) == "bar");
    assert(!name.isIndexed(0));
    assert(name.isIndexed(1));
}

@("ofNameWhenDoubleRunOnAndAssociative") unittest
{
    auto name = Name.of("foo[bar]baz");
    assert(name.toString() == "foo[bar].baz");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(1, Form.ORIGINAL) == "bar");
    assert(name.getElement(2, Form.ORIGINAL) == "baz");
    assert(!name.isIndexed(0));
    assert(name.isIndexed(1));
    assert(!name.isIndexed(2));
}

@("ofNameWhenDoubleDotAndAssociative") unittest
{
    auto name = Name.of("foo.[bar].baz");
    assert(name.toString() == "foo[bar].baz");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(1, Form.ORIGINAL) == "bar");
    assert(name.getElement(2, Form.ORIGINAL) == "baz");
    assert(!name.isIndexed(0));
    assert(name.isIndexed(1));
    assert(!name.isIndexed(2));
}

@("ofNameWhenMissingCloseBracket") unittest
{
    invalid("[bar");
}

@("ofNameWhenMissingCloseBracketAtEndOfName") unittest
{
    invalid("foo[");
}

@("ofNameWhenOnlyMissingCloseBracket") unittest
{
    invalid("[");
}

@("ofNameWhenMissingOpenBracket") unittest
{
    invalid("bar]");
}

@("ofNameWhenMultipleMismatchedBrackets") unittest
{
    invalid("[a[[[b]ar]");
}

@("ofNameWhenNestedBrackets") unittest
{
    auto name = Name.of("foo[a[c][[b]ar]]");
    assert(name.toString() == "foo[a[c][[b]ar]]");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(1, Form.ORIGINAL) == "a[c][[b]ar]");
}

@("ofNameWithWhitespaceInName") unittest
{
    invalid("foo. bar");
}

@("ofNameWithWhitespaceInAssociativeElement") unittest
{
    auto name = Name.of("foo[b a r]");
    assert(name.toString() == "foo[b a r]");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(1, Form.ORIGINAL) == "b a r");
    assert(!name.isIndexed(0));
    assert(name.isIndexed(1));
}

@("ofNameWithUppercaseInAssociativeElement") unittest
{
    auto name = Name.of("foo[BAR]");
    assert(name.toString() == "foo[BAR]");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(1, Form.ORIGINAL) == "BAR");
    assert(!name.isIndexed(0));
    assert(name.isIndexed(1));
}

@("ofWhenNameIsEmptyShouldReturnEmptyName") unittest
{
    auto name = Name.of("");
    assert(name.toString() == "");
    assert(name.append("foo").toString() == "foo");
}

@("ofIfValidWhenNameIsValidReturnsName") unittest
{
    assert(Name.ofIfValid("spring.bo-ot").toString() == "spring.bo-ot");
}

@("ofIfValidWhenNameIsNotValidReturnsNull") unittest
{
    assert(Name.ofIfValid("spring.bo!oot") is null);
}

@("adaptWhenNameIsNullShouldThrowException") unittest
{
    assertThrows!IllegalArgumentException(() { Name.adapt(null, '.'); }, "Name must not be null");
}

@("adaptWhenElementValueProcessorIsNullShouldAdapt") unittest
{
    assert(Name.adapt("foo", '.', null).toString() == "foo");
}

@("adaptShouldCreateName") unittest
{
    assert(Name.adapt("foo.bar.baz", '.') == Name.of("foo.bar.baz"));
}

@("adaptShouldStripInvalidChars") unittest
{
    auto name = Name.adapt("f@@.b%r", '.');
    assert(name.getElement(0, Form.UNIFORM) == "f");
    assert(name.getElement(0, Form.ORIGINAL) == "f");
    assert(name.getElement(1, Form.UNIFORM) == "br");
    assert(name.getElement(1, Form.ORIGINAL) == "br");
    assert(name.toString() == "f.br");
}

@("adaptShouldSupportUnderscore") unittest
{
    auto name = Name.adapt("f-_o.b_r", '.');
    assert(name.getElement(0, Form.UNIFORM) == "fo");
    assert(name.getElement(0, Form.ORIGINAL) == "f-_o");
    assert(name.getElement(1, Form.UNIFORM) == "br");
    assert(name.getElement(1, Form.ORIGINAL) == "b_r");
    assert(name.toString() == "f-o.br");
}

@("adaptShouldSupportMixedCase") unittest
{
    auto name = Name.adapt("fOo.bAr", '.');
    assert(name.getElement(0, Form.UNIFORM) == "foo");
    assert(name.getElement(0, Form.ORIGINAL) == "fOo");
    assert(name.getElement(1, Form.UNIFORM) == "bar");
    assert(name.getElement(1, Form.ORIGINAL) == "bAr");
    assert(name.toString() == "foo.bar");
}

@("adaptShouldUseElementValueProcessor") unittest
{
    import std.array : replace;

    auto name = Name.adapt("FOO_THE-BAR", '_', (string c) => c.replace("-", ""));
    assert(name.toString() == "foo.thebar");
}

@("adaptShouldSupportIndexedElements") unittest
{
    auto name = Name.adapt("foo", '.');
    assert(name.toString() == "foo" && name.getNumberOfElements() == 1);
    name = Name.adapt("[foo]", '.');
    assert(name.toString() == "[foo]" && name.getNumberOfElements() == 1);
    name = Name.adapt("foo.bar", '.');
    assert(name.toString() == "foo.bar" && name.getNumberOfElements() == 2);
    name = Name.adapt("foo[foo.bar]", '.');
    assert(name.toString() == "foo[foo.bar]" && name.getNumberOfElements() == 2);
    name = Name.adapt("foo.[bar].baz", '.');
    assert(name.toString() == "foo[bar].baz" && name.getNumberOfElements() == 3);
}

@("adaptUnderscoreShouldReturnEmpty") unittest
{
    assert(Name.adapt("_", '_').isEmpty());
    assert(Name.adapt("_", '.').isEmpty());
}

@("adaptWhenNameEndsWithOpenBracketShouldNotAddEmptyElement") unittest
{
    auto name = Name.adapt("foo[", '.');
    assert(name.getNumberOfElements() == 1);
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
}

@("adaptWhenNameIsOnlyAnOpenBracketShouldReturnEmpty") unittest
{
    assert(Name.adapt("[", '.').isEmpty());
}

@("isEmptyWhenEmptyShouldReturnTrue") unittest
{
    assert(Name.of("").isEmpty());
}

@("isEmptyWhenNotEmptyShouldReturnFalse") unittest
{
    assert(!Name.of("x").isEmpty());
}

@("isLastElementIndexedWhenIndexedShouldReturnTrue") unittest
{
    assert(Name.of("foo[0]").isLastElementIndexed());
}

@("isLastElementIndexedWhenNotIndexedShouldReturnFalse") unittest
{
    assert(!Name.of("foo.bar").isLastElementIndexed());
    assert(!Name.of("foo[0].bar").isLastElementIndexed());
}

@("getLastElementShouldGetLastElement") unittest
{
    auto name = Name.adapt("foo.bAr", '.');
    assert(name.getLastElement(Form.ORIGINAL) == "bAr");
    assert(name.getLastElement(Form.UNIFORM) == "bar");
}

@("getLastElementWhenEmptyShouldReturnEmptyString") unittest
{
    assert(Name.EMPTY.getLastElement(Form.ORIGINAL) == "");
    assert(Name.EMPTY.getLastElement(Form.UNIFORM) == "");
}

@("getElementShouldNotIncludeAngleBrackets") unittest
{
    auto name = Name.of("[foo]");
    assert(name.getElement(0, Form.ORIGINAL) == "foo");
    assert(name.getElement(0, Form.UNIFORM) == "foo");
}

@("getElementInUniformFormShouldNotIncludeDashes") unittest
{
    auto name = Name.of("f-o-o");
    assert(name.getElement(0, Form.ORIGINAL) == "f-o-o");
    assert(name.getElement(0, Form.UNIFORM) == "foo");
}

private string[] elementsOf(string text, Form form)
{
    auto name = Name.of(text);
    string[] result;
    foreach (i; 0 .. name.getNumberOfElements())
        result ~= name.getElement(i, form);
    return result;
}

@("getElementInOriginalFormShouldReturnElement") unittest
{
    assert(elementsOf("foo.bar", Form.ORIGINAL) == ["foo", "bar"]);
    assert(elementsOf("foo[0]", Form.ORIGINAL) == ["foo", "0"]);
    assert(elementsOf("foo.[0]", Form.ORIGINAL) == ["foo", "0"]);
    assert(elementsOf("foo[baz]", Form.ORIGINAL) == ["foo", "baz"]);
    assert(elementsOf("foo.baz", Form.ORIGINAL) == ["foo", "baz"]);
    assert(elementsOf("foo[baz].bar", Form.ORIGINAL) == ["foo", "baz", "bar"]);
    assert(elementsOf("foo.baz.bar", Form.ORIGINAL) == ["foo", "baz", "bar"]);
    assert(elementsOf("foo.baz-bar", Form.ORIGINAL) == ["foo", "baz-bar"]);
}

@("getElementInUniformFormShouldReturnElement") unittest
{
    assert(elementsOf("foo.bar", Form.UNIFORM) == ["foo", "bar"]);
    assert(elementsOf("foo[0]", Form.UNIFORM) == ["foo", "0"]);
    assert(elementsOf("foo.[0]", Form.UNIFORM) == ["foo", "0"]);
    assert(elementsOf("foo[baz]", Form.UNIFORM) == ["foo", "baz"]);
    assert(elementsOf("foo.baz", Form.UNIFORM) == ["foo", "baz"]);
    assert(elementsOf("foo[baz].bar", Form.UNIFORM) == ["foo", "baz", "bar"]);
    assert(elementsOf("foo.baz.bar", Form.UNIFORM) == ["foo", "baz", "bar"]);
    assert(elementsOf("foo.baz-bar", Form.UNIFORM) == ["foo", "bazbar"]);
}

@("getNumberOfElementsShouldReturnNumberOfElement") unittest
{
    assert(Name.of("").getNumberOfElements() == 0);
    assert(Name.of("x").getNumberOfElements() == 1);
    assert(Name.of("x.y").getNumberOfElements() == 2);
    assert(Name.of("x[0].y").getNumberOfElements() == 3);
}

@("appendWhenNotIndexedShouldAppendWithDot") unittest
{
    assert(Name.of("foo").append("bar").toString() == "foo.bar");
}

@("appendWhenIndexedShouldAppendWithBrackets") unittest
{
    auto name = Name.of("foo").append("[bar]");
    assert(name.isLastElementIndexed());
    assert(name.toString() == "foo[bar]");
}

@("appendWhenElementNameIsNotValidShouldThrowException") unittest
{
    assertThrows!InvalidConfigurationPropertyNameException(() { Name.of("foo").append("-bar"); },
            "Configuration property name '-bar' is not valid");
}

@("appendWhenElementNameMultiDotShouldAppend") unittest
{
    auto name = Name.of("foo").append("bar.baz");
    assert(name.toString() == "foo.bar.baz");
    assert(name.getNumberOfElements() == 3);
}

@("appendWhenElementNameIsNullShouldReturnName") unittest
{
    auto name = Name.of("foo");
    assert(name.append(cast(string) null) is name);
}

@("appendConfigurationPropertyNameShouldReturnAppendedName") unittest
{
    assert(Name.of("spring.boot").append(Name.of("tests.code")).toString() == "spring.boot.tests.code");
}

@("appendConfigurationPropertyNameWhenNullShouldReturnName") unittest
{
    auto name = Name.of("foo");
    assert(name.append(cast(Name) null) is name);
}

@("getParentShouldReturnParent") unittest
{
    auto name = Name.of("this.is.a.multipart.name");
    auto p1 = name.getParent();
    auto p2 = p1.getParent();
    auto p3 = p2.getParent();
    auto p4 = p3.getParent();
    auto p5 = p4.getParent();
    assert(p1.toString() == "this.is.a.multipart");
    assert(p2.toString() == "this.is.a");
    assert(p3.toString() == "this.is");
    assert(p4.toString() == "this");
    assert(p5.equals(Name.EMPTY));
}

@("getParentWhenEmptyShouldReturnEmpty") unittest
{
    assert(Name.empty().getParent().equals(Name.EMPTY));
}

@("chopWhenLessThenSizeShouldReturnChopped") unittest
{
    auto name = Name.of("foo.bar.baz");
    assert(name.chop(1).toString() == "foo");
    assert(name.chop(2).toString() == "foo.bar");
}

@("chopWhenGreaterThanSizeShouldReturnExisting") unittest
{
    auto name = Name.of("foo.bar.baz");
    assert(name.chop(4) == name);
}

@("chopWhenEqualToSizeShouldReturnExisting") unittest
{
    auto name = Name.of("foo.bar.baz");
    assert(name.chop(3) == name);
}

@("subNameWhenOffsetLessThanSizeShouldReturnSubName") unittest
{
    auto name = Name.of("foo.bar.baz");
    assert(name.subName(1).toString() == "bar.baz");
    assert(name.subName(2).toString() == "baz");
}

@("subNameOfAdaptedNameWhenOffsetLessThanSizeShouldReturnSubName") unittest
{
    auto name = Name.adapt("MY_LOGGING_LEVEL_ONE", '_');
    assert(name.subName(1).toString() == "logging.level.one");
    assert(name.subName(2).toString() == "level.one");
}

@("subNameOfAdaptedNameWithValueProcessorWhenOffsetLessThanSizeShouldReturnSubName") unittest
{
    import std.uni : toLower;

    auto name = Name.adapt("MY_LOGGING_LEVEL_ONE", '_', (string value) => value.toLower);
    assert(name.subName(1).toString() == "logging.level.one");
    assert(name.subName(2).toString() == "level.one");
}

@("subNameWhenOffsetZeroShouldReturnName") unittest
{
    auto name = Name.of("foo.bar.baz");
    assert(name.subName(0) is name);
}

@("subNameWhenOffsetEqualToSizeShouldReturnEmpty") unittest
{
    // Upstream asserts identity with EMPTY; Flint returns an equal empty name (EMPTY is immutable).
    assert(Name.of("foo.bar.baz").subName(3).equals(Name.EMPTY));
}

@("subNameWhenOffsetMoreThanSizeShouldReturnEmpty") unittest
{
    auto name = Name.of("foo.bar.baz");
    assertThrows!IndexOutOfBoundsException(() { name.subName(4); });
}

@("subNameWhenOffsetNegativeShouldThrowException") unittest
{
    auto name = Name.of("foo.bar.baz");
    assertThrows!IndexOutOfBoundsException(() { name.subName(-1); });
}

@("isParentOfWhenSameShouldReturnFalse") unittest
{
    auto name = Name.of("foo");
    assert(!name.isParentOf(name));
}

@("isParentOfWhenParentShouldReturnTrue") unittest
{
    auto name = Name.of("foo");
    auto child = Name.of("foo.bar");
    assert(name.isParentOf(child));
    assert(!child.isParentOf(name));
}

@("isParentOfWhenGrandparentShouldReturnFalse") unittest
{
    auto name = Name.of("foo");
    auto grandchild = Name.of("foo.bar.baz");
    assert(!name.isParentOf(grandchild));
    assert(!grandchild.isParentOf(name));
}

@("isParentOfWhenRootReturnTrue") unittest
{
    auto name = Name.of("");
    auto child = Name.of("foo");
    auto grandchild = Name.of("foo.bar");
    assert(name.isParentOf(child));
    assert(!name.isParentOf(grandchild));
    assert(!child.isAncestorOf(name));
}

@("isAncestorOfWhenSameShouldReturnFalse") unittest
{
    auto name = Name.of("foo");
    assert(!name.isAncestorOf(name));
}

@("isAncestorOfWhenParentShouldReturnTrue") unittest
{
    auto name = Name.of("foo");
    auto child = Name.of("foo.bar");
    assert(name.isAncestorOf(child));
    assert(!child.isAncestorOf(name));
}

@("isAncestorOfWhenGrandparentShouldReturnTrue") unittest
{
    auto name = Name.of("foo");
    auto grandchild = Name.of("foo.bar.baz");
    assert(name.isAncestorOf(grandchild));
    assert(!grandchild.isAncestorOf(name));
}

@("isAncestorOfWhenRootShouldReturnTrue") unittest
{
    auto name = Name.of("");
    auto grandchild = Name.of("foo.bar.baz");
    assert(name.isAncestorOf(grandchild));
    assert(!grandchild.isAncestorOf(name));
}

@("compareShouldSortNames") unittest
{
    import std.algorithm.iteration : map;
    import std.algorithm.sorting : sort;
    import std.array : array;

    const sorted = [
        Name.of("foo[10]"), Name.of("foo.bard"), Name.of("foo[2]"), Name.of("foo.bar"),
        Name.of("foo.baz"), Name.of("foo")
    ].sort!((a, b) => a.compareTo(b) < 0)
        .map!(n => n.toString())
        .array;
    assert(sorted == ["foo", "foo[2]", "foo[10]", "foo.bar", "foo.bard", "foo.baz"]);
}

@("compareDifferentLengthsShouldSortNames") unittest
{
    auto name = Name.of("spring.web.resources.chain.strategy.content");
    auto other = Name.of("spring.web.resources.chain.strategy.content.enabled");
    assert(name.compareTo(other) < 0);
}

@("toStringShouldBeLowerCaseDashed") unittest
{
    assert(Name.adapt("fOO.b_-a-r", '.').toString() == "foo.b-a-r");
}

@("toStringFromOfShouldBeLowerCaseDashed") unittest
{
    assert(Name.of("foo.bar-baz").toString() == "foo.bar-baz");
}

@("equalsAndHashCode") unittest
{
    auto n01 = Name.of("foo[bar]");
    auto n02 = Name.of("foo[bar]");
    auto n03 = Name.of("foo.bar");
    auto n04 = Name.of("f-o-o.b-a-r");
    auto n05 = Name.of("foo[BAR]");
    auto n06 = Name.of("oof[bar]");
    auto n07 = Name.of("foo.bar");
    auto n08 = Name.EMPTY;
    auto n09 = Name.of("foo");
    auto n10 = Name.of("fo");
    auto n11 = Name.adapt("foo.BaR", '.');
    auto n12 = Name.of("f-o-o[b-a-r]");
    auto n13 = Name.of("f-o-o[b-a-r--]");
    auto n14 = Name.of("[1]");
    auto n15 = Name.of("[-1]");
    assert(n01.equals(n01) && n01.hashCode() == n01.hashCode());
    assert(n01.equals(n02) && n01.hashCode() == n02.hashCode());
    assert(n01.equals(n03) && n01.hashCode() == n03.hashCode());
    assert(n01.equals(n04) && n01.hashCode() == n04.hashCode());
    assert(n11.equals(n03) && n11.hashCode() == n03.hashCode());
    assert(n03.equals(n11) && n03.hashCode() == n11.hashCode());
    assert(!n01.equals(n05));
    assert(!n01.equals(n06));
    assert(!n07.equals(n08));
    assert(!n09.equals(n10));
    assert(!n10.equals(n09));
    assert(!n12.equals(n13));
    assert(!n14.equals(n15));
}

@("equalsAndHashCodeAfterOperations") unittest
{
    auto n1 = Name.of("nested");
    auto n2 = Name.empty().append("nested");
    auto n3 = Name.of("nested.value").getParent();
    assert(n1.hashCode() == n2.hashCode() && n2.hashCode() == n3.hashCode());
    assert(n1.equals(n2) && n2.equals(n3));
}

@("equalsWhenStartsWith") unittest
{
    assert(!Name.of("my.sources[0].xame").equals(Name.of("my.sources[0].xamespace")));
}

@("equalsWhenStartsWithOfAdaptedName") unittest
{
    assert(!Name.adapt("example.mymap.ALPHA", '.').equals(Name.adapt("example.mymap.ALPHA_BRAVO", '.')));
}

@("equalsWhenStartsWithOfAdaptedNameOfIllegalChars") unittest
{
    assert(!Name.adapt("example.mymap.ALPH!", '.').equals(Name.adapt("example.mymap.ALPHA!BRAVO", '.')));
}

@("equalsWhenNameStartsTheSameUsingDashedCompare") unittest
{
    auto n1 = Name.of("management.metrics.web.server.auto-time-request");
    auto n2 = Name.of("management.metrics.web.server.auto-time-requests");
    assert(!n1.equals(n2));
    assert(!n2.equals(n1));
}

@("equalsWhenAdaptedNameMatchesDueToRemovalOfTrailingNonUniformCharacters") unittest
{
    auto name1 = Name.of("example.demo");
    auto name2 = Name.adapt("example.demo$$", '.');
    assert(name1.equals(name2));
    assert(name2.equals(name1));
}

@("equalsSymmetricWhenNameMatchesDueToIgnoredTrailingDashes") unittest
{
    auto n1 = Name.of("example.demo");
    auto n2 = Name.of("example.demo--");
    assert(n2.equals(n1));
    assert(n1.equals(n2));
}

@("isValidWhenValidShouldReturnTrue") unittest
{
    foreach (name; [
        "", "foo", "foo.bar", "foo[0]", "foo[0].baz", "foo.b1", "foo.b-a-r", "foo[FooBar].baz"
    ])
        assert(Name.isValid(name), name);
}

@("isValidWhenNotValidShouldReturnFalse") unittest
{
    assert(!Name.isValid(null));
    foreach (name; ["-foo", "FooBar", "foo!bar", "foo["])
        assert(!Name.isValid(name), name);
}

@("hasIndexedElementWhenHasIndexedElementReturnsTrue") unittest
{
    assert(Name.of("foo[bar]").hasIndexedElement());
}

@("hasIndexedElementWhenHasNoIndexedElementReturnsFalse") unittest
{
    assert(!Name.of("foo.bar").hasIndexedElement());
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
