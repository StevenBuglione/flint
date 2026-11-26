module mapping_alias_tests;

import flint.data.mapping : Alias;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : NoSuchElementException;
import std.exception : assertThrown;

@safe:

private class Label
{
    private string text;

    this(string text)
    {
        this.text = text;
    }

    override bool opEquals(const Object other) const
    {
        auto label = cast(const Label) other;
        return label !is null && label.text == text;
    }

    override size_t toHash() const nothrow
    {
        return text.length;
    }

    override string toString() const
    {
        return text;
    }
}

private final class MappedLabel : Label
{
    this(string text)
    {
        super(text);
    }
}

@("type aliases share absence and distinguish a present empty string")
unittest
{
    assert(Alias.empty() is Alias.NONE);
    assert(Alias.ofNullable(Any.of(cast(Label) null)) is Alias.NONE);
    assert(Alias.NONE.isEmpty() && !Alias.NONE.isPresent());
    assert(Alias.NONE.getValue().isNull() && Alias.NONE.hashCode() == 0);
    assert(Alias.NONE.toString() == "NONE");
    assert(Alias.NONE.mapTyped!long.isNull && Alias.NONE.mapTyped!Label is null);
    assertThrown!IllegalArgumentException(Alias.of(Any.init));
    assertThrown!NoSuchElementException(Alias.NONE.getRequiredValue());

    auto emptyText = Alias.of(Any.of(""));
    assert(emptyText.isPresent() && !emptyText.isEmpty());
    assert(emptyText.hasValue(Any.of("")));
    assert(!emptyText.hasValue(Any.of(cast(string) null)));
    assert(emptyText.getRequiredValue().get!string == "");
    assert(emptyText.isPresentButDifferent(Alias.NONE));
    assert(!Alias.NONE.isPresentButDifferent(emptyText));
    assertThrown!IllegalArgumentException(emptyText.isPresentButDifferent(null));
}

@("alias equality calls the value's equality and typed reads preserve assignability")
unittest
{
    auto label = new MappedLabel("pets");
    auto left = Alias.of(Any.of(label));
    auto right = Alias.of(Any.of(new MappedLabel("pets")));
    assert(left.equals(right) && left == right && left.hashCode() == right.hashCode());
    assert(left.hasSamePresentValueAs(right) && !left.isPresentButDifferent(right));
    assert(left.hasValue(Any.of(new Label("pets"))));
    assert(left.mapTyped!Label is label && left.getValue().asObject() is label);
    assert(left.mapTyped!int.isNull);
    assert(left.toString() == "pets");

    auto number = Alias.of(Any.of(7));
    assert(number.mapTyped!int.get == 7 && number.mapTyped!long.isNull);
    assert(!number.equals(Alias.of(Any.of(7L))));
    assert(number.mapTyped!Any
            .get
            .get!int == 7);
    assert(Alias.of(Any.of("pets")).hashCode() == 3_437_364);
}

@("boxed floating aliases retain NaN equality and distinguish signed zero")
unittest
{
    auto nan = Alias.of(Any.of(double.nan));
    auto anotherNan = Alias.of(Any.of(-double.nan));
    assert(nan == anotherNan && nan.hashCode() == anotherNan.hashCode());
    assert(Alias.of(Any.of(0.0)) != Alias.of(Any.of(-0.0)));
    assert(Alias.of(Any.of(1.0f)).hashCode() == 0x3f80_0000);
}
