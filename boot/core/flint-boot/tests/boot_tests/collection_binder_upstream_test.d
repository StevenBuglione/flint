// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/bind/CollectionBinderTests.java: the tests boot_tests/collection_binder_test.d does not port.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; `List`, `Set` and `EnumSet` are
// `flint.java.util`'s `List` and `Set`; records become D structs (classes when they hold references) with the binding
// constructor Flint AOT emits; the system environment source is `SystemEnvironmentPropertySource`;
// `Collections.unmodifiableList(null)` throwing is a getter that throws when the list is null.
// Not ported: bindToCollectionShouldUsePropertyEditor and bindToCollectionWhenStringShouldUsePropertyEditor (java.beans
// PropertyEditor converting class names to `Class` objects).
module boot_tests.collection_binder_upstream_test;

import boot_tests.upstream_support : NonIterableSource, binderOf, source, valueObject;
import flint.boot.context.properties.bind : BindException, BindResult, Bindable;
import flint.boot.context.properties.source : ConfigurationPropertySource, SystemEnvironmentPropertySource;
import flint.java.util : ArrayList, LinkedHashSet, List, Set;

@safe:

/// `CollectionBinderTests.ExampleEnum`.
enum ExampleEnum
{
    FOO_BAR,
    BAR_BAZ
}

/// `ExampleCollectionBean`.
final class ExampleCollectionBean
{
    private List!string items;
    private Set!string itemsSet;
    private string string_;

    /// Part of the upstream test fixture.
    this()
    {
        items = new ArrayList!string;
        itemsSet = new LinkedHashSet!string;
    }

    List!string getItems()
    {
        return items;
    }

    void setItems(List!string)
    {
        this.items.add("d");
    }

    Set!string getItemsSet()
    {
        return itemsSet;
    }

    void setItemsSet(Set!string itemsSet)
    {
        this.itemsSet = itemsSet;
    }

    string getString()
    {
        return string_;
    }

    void setString(string value)
    {
        this.string_ = value;
    }
}

/// `BeanWithNestedCollection`.
final class BeanWithNestedCollection
{
    private string value;
    private List!BeanWithNestedCollection foos;

    List!BeanWithNestedCollection getFoos()
    {
        return foos;
    }

    void setFoos(List!BeanWithNestedCollection foos)
    {
        this.foos = foos;
    }

    string getValue()
    {
        return value;
    }

    void setValue(string value)
    {
        this.value = value;
    }
}

/// `ClonedArrayBean`.
final class ClonedArrayBean
{
    private string[] bar;

    string[] getBar()
    {
        return bar is null ? null : bar.dup;
    }

    void setBar(string[] bar)
    {
        this.bar = bar;
    }
}

/// `BeanWithGetterException`.
final class BeanWithGetterException
{
    private List!string values;

    void setValues(List!string values)
    {
        this.values = values;
    }

    List!string getValues()
    {
        import flint.java.lang : NullPointerException;

        if (values is null)
            throw new NullPointerException("Collections.unmodifiableList(null)");
        return values;
    }
}

/// `BeanWithEnumSetCollection`.
final class BeanWithEnumSetCollection
{
    private List!(Set!ExampleEnum) values;

    void setValues(List!(Set!ExampleEnum) values)
    {
        this.values = values;
    }

    List!(Set!ExampleEnum) getValues()
    {
        return values;
    }
}

/// `Name`.
struct Name
{
    /// First name.
    string first;
    /// Last name.
    string last;

    /// Part of the upstream test fixture.
    this(string first, string last)
    {
        this.first = first;
        this.last = last;
    }
}

/// `BeanWithCamelCaseNameList` (a class: a struct holding a class reference cannot be boxed in @safe code).
final class BeanWithCamelCaseNameList
{
    /// The names.
    List!Name theNames;

    /// Part of the upstream test fixture.
    this(List!Name theNames)
    {
        this.theNames = theNames;
    }
}

@("bindToSetShouldReturnPopulatedCollection") unittest
{
    auto result = binderOf([source([["foo[0]", "a"], ["foo[1]", "b"], ["foo[2]", "c"]])]).bind!(
            Set!string)("foo").get();
    assert(result.toArray() == ["a", "b", "c"]);
}

@("bindToCollectionWhenNestedShouldReturnPopulatedCollection") unittest
{
    auto result = binderOf!(List!int)([
        source([["foo[0][0]", "1"], ["foo[0][1]", "2"], ["foo[1][0]", "3"], ["foo[1][1]", "4"]])
    ]).bind!(List!(List!int))("foo").get();
    assert(result.size() == 2);
    assert(result.get(0).toArray() == [1, 2]);
    assert(result.get(1).toArray() == [3, 4]);
}

version (FlintUnboundIndexedElements)
{
    // Gap: binding stops at the first missing or unbindable index instead of failing with
    // UnboundConfigurationPropertiesException.
    import flint.boot.context.properties.bind : UnboundConfigurationPropertiesException;
    import boot_tests.java_bean_binder_upstream_test : JavaBean = ExampleValueBean;

    private void assertSingleUnbound(BindException ex, string name, string value)
    {
        auto cause = cast(UnboundConfigurationPropertiesException) ex.next;
        assert(cause !is null);
        auto unbound = cause.getUnboundProperties();
        assert(unbound.length == 1);
        assert(unbound[0].getName().toString() == name);
        assert(unbound[0].getValue() == value);
    }

    @("bindToCollectionWhenNonSequentialShouldThrowException") unittest
    {
        try
        {
            binderOf([source([["foo[0]", "2"], ["foo[1]", "1"], ["foo[3]", "3"]])]).bind!(List!int)("foo");
            assert(false, "expected a BindException");
        }
        catch (BindException ex)
            assertSingleUnbound(ex, "foo[3]", "3");
    }

    @("bindToCollectionWhenNonKnownIndexedChildNotBoundThrowsException") unittest
    {
        // gh-45994
        try
        {
            binderOf([
                source([
                    ["foo[0].first", "Spring"], ["foo[0].last", "Boot"], ["foo[1].missing", "bad"]
                ])
            ], valueObject!Name()).bind!(List!Name)("foo");
            assert(false, "expected a BindException");
        }
        catch (BindException ex)
            assertSingleUnbound(ex, "foo[1].missing", "bad");
    }

    @("bindToNonScalarCollectionWhenNonSequentialShouldThrowException") unittest
    {
        try
        {
            binderOf!JavaBean([
                source([["foo[0].value", "1"], ["foo[1].value", "2"], ["foo[4].value", "4"]])
            ]).bind!(List!JavaBean)("foo");
            assert(false, "expected a BindException");
        }
        catch (BindException ex)
            assertSingleUnbound(ex, "foo[4].value", "4");
    }
}

version (FlintBindIntoExistingCollection)
{
    // Gap: a collection property is not bound into the collection its getter returns before the setter is called
    // (Boot binds into `items` and then calls `setItems`, which appends "d").
    @("bindToNestedCollectionWhenNonKnownIndexed") unittest
    {
        // gh-46039
        auto list = binderOf!(ExampleCollectionBean, List!string, Set!string)([
            source([["foo[0].items[0]", "a"], ["foo[0].items[1]", "b"], ["foo[0].string", "test"]])
        ]).bind!(List!ExampleCollectionBean)("foo").get();
        assert(list.size() == 1);
        assert(list.get(0).getItems().toArray() == ["a", "b", "d"]);
        assert(list.get(0).getString() == "test");
    }

    @("bindToCollectionShouldAlsoCallSetterIfPresent") unittest
    {
        auto result = binderOf!(List!string, Set!string)([source([["foo.items", "a,b,c"]])])
            .bind!ExampleCollectionBean("foo").get();
        assert(result.getItems().size() == 4);
        assert(result.getItems().toArray() == ["a", "b", "c", "d"]);
    }
}

version (FlintNonIterableSourceBinding)
{
    // Gap: indexed elements are not bound from a source that cannot list its names (containsDescendantOf UNKNOWN).
    @("bindToCollectionWhenNonIterableShouldReturnPopulatedCollection") unittest
    {
        auto result = binderOf([
            new NonIterableSource(source([["foo[1]", "2"], ["foo[0]", "1"], ["foo[2]", "3"]]))
        ]).bind!(List!int)("foo").get();
        assert(result.toArray() == [1, 2, 3]);
    }
}

@("bindToCollectionWhenHasExistingCollectionButNoValueShouldReturnUnbound") unittest
{
    auto existing = new ArrayList!int;
    existing.add(1000);
    BindResult!(List!int) result = binderOf([source([["faf[0]", "1"]])]).bind!(List!int)("foo",
            Bindable!(List!int).of().withExistingValue(existing));
    assert(!result.isBound());
}

@("bindToCollectionWhenItemContainsCommasShouldReturnPopulatedCollection") unittest
{
    auto result = binderOf([source([["foo[0]", "1,2"], ["foo[1]", "3"]])]).bind!(List!string)("foo").get();
    assert(result.toArray() == ["1,2", "3"]);
}

@("bindToImmutableCollectionShouldReturnPopulatedCollection") unittest
{
    Set!string empty = new LinkedHashSet!string;
    auto result = binderOf([source([["foo.values", "a,b,c"]])]).bind!(Set!string)("foo.values",
            Bindable!(Set!string).of().withExistingValue(empty)).get();
    assert(result.size() == 3);
}

version (FlintCustomCollectionTypes)
{
    // Gap: a property typed as a custom collection class (an ArrayList subclass) gets a plain List, which the
    // setter cannot take ("Any holds List!string").

    /// `MyCustomNoDefaultConstructorList`.
    final class MyCustomNoDefaultConstructorList : ArrayList!string
    {
        /// Part of the upstream test fixture.
        this(string[] items)
        {
            foreach (item; items)
                add(item);
        }
    }

    /// `ExampleCustomNoDefaultConstructorBean`.
    final class ExampleCustomNoDefaultConstructorBean
    {
        private MyCustomNoDefaultConstructorList items;

        /// Part of the upstream test fixture.
        this()
        {
            items = new MyCustomNoDefaultConstructorList(["foo"]);
        }

        MyCustomNoDefaultConstructorList getItems()
        {
            return items;
        }

        void setItems(MyCustomNoDefaultConstructorList items)
        {
            this.items = items;
        }
    }

    /// `MyCustomWithDefaultConstructorList`.
    final class MyCustomWithDefaultConstructorList : ArrayList!string
    {
    }

    /// `ExampleCustomWithDefaultConstructorBean`.
    final class ExampleCustomWithDefaultConstructorBean
    {
        private MyCustomWithDefaultConstructorList items;

        /// Part of the upstream test fixture.
        this()
        {
            items = new MyCustomWithDefaultConstructorList;
        }

        MyCustomWithDefaultConstructorList getItems()
        {
            return items;
        }

        void setItems(MyCustomWithDefaultConstructorList items)
        {
            this.items.clear();
            foreach (item; items.toArray())
                this.items.add(item);
        }
    }

    @("bindToCollectionWithNoDefaultConstructor") unittest
    {
        auto result = binderOf!MyCustomNoDefaultConstructorList([source([["foo.items", "a,b,c,c"]])])
            .bind!ExampleCustomNoDefaultConstructorBean("foo").get();
        assert(result.getItems().size() == 4);
        assert(result.getItems().toArray() == ["a", "b", "c", "c"]);
    }

    @("bindToCollectionWithDefaultConstructor") unittest
    {
        // gh-12322
        auto result = binderOf!MyCustomWithDefaultConstructorList([
            source([["foo.items", "a,b,c,c"]])
        ]).bind!ExampleCustomWithDefaultConstructorBean("foo").get();
        assert(result.getItems().size() == 4);
        assert(result.getItems().toArray() == ["a", "b", "c", "c"]);
    }
}

@("bindToSetShouldNotAllowDuplicateValues") unittest
{
    auto result = binderOf!(List!string, Set!string)([source([["foo.items-set", "a,b,c,c"]])])
        .bind!ExampleCollectionBean("foo").get();
    assert(result.getItemsSet().size() == 3);
    assert(result.getItemsSet().toArray() == ["a", "b", "c"]);
}

version (FlintEmptyStringNonScalarCollection)
{
    // Gap: an empty value does not bind an empty collection of beans (the list stays null).
    @("bindToNestedCollectionWhenEmptyStringShouldReturnEmptyCollection") unittest
    {
        auto foo = binderOf!(List!BeanWithNestedCollection)([
            source([["foo.value", "one"], ["foo.foos", ""]])
        ]).bind!BeanWithNestedCollection("foo").get();
        assert(foo.getValue() == "one");
        assert(foo.getFoos() !is null && foo.getFoos().isEmpty());
    }
}

@("bindToBeanWithNestedCollectionAndNonIterableSourceShouldNotFail") unittest
{
    // gh-10702
    binderOf!(List!BeanWithNestedCollection)([new NonIterableSource(source(null))])
        .bind!BeanWithNestedCollection("foo");
}

@("bindToBeanWithClonedArray") unittest
{
    auto bean = binderOf!(string[])([source([["foo.bar[0]", "hello"]])]).bind!ClonedArrayBean("foo").get();
    assert(bean.getBar() == ["hello"]);
}

version (FlintGetterInvocation)
{
    // Gap: the binder calls the getter of a collection property it is about to replace, and lets its exception
    // escape.
    @("bindToBeanWithExceptionInGetterForExistingValue") unittest
    {
        auto result = binderOf!(List!string)([source([["foo.values", "a,b,c"]])]).bind!BeanWithGetterException("foo")
            .get();
        assert(result.getValues().toArray() == ["a", "b", "c"]);
    }
}

@("bindToBeanWithEnumSetCollection") unittest
{
    auto result = binderOf!(ExampleEnum, Set!ExampleEnum, List!(Set!ExampleEnum))([
        source([["foo.values[0]", "foo-bar,bar-baz"]])
    ]).bind!BeanWithEnumSetCollection("foo").get();
    auto values = result.getValues();
    assert(values !is null);
    assert(values.get(0).toArray() == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
}

private void assertNames(BeanWithCamelCaseNameList result)
{
    assert(result.theNames.toArray() == [Name("spring", "boot"), Name("binding", "test")]);
}

@("bindToWellFormedSystemEnvironmentVariableProperty") unittest
{
    // gh-46184
    auto environment = new SystemEnvironmentPropertySource([
        "FOO_THENAMES_0_FIRST": "spring",
        "FOO_THENAMES_0_LAST": "boot",
        "FOO_THENAMES_1_FIRST": "binding",
        "FOO_THENAMES_1_LAST": "test"
    ]);
    assertNames(binderOf!(List!Name)([environment], valueObject!Name(),
            valueObject!BeanWithCamelCaseNameList()).bind!BeanWithCamelCaseNameList("foo").get());
}

version (FlintLegacySystemEnvironmentNames)
{
    // Gap: `FOO_THE_NAMES_0_FIRST` (Boot's legacy form) does not bind `foo.the-names[0].first`.
    @("bindToLegacySystemEnvironmentVariableProperty") unittest
    {
        // gh-46184
        auto environment = new SystemEnvironmentPropertySource([
            "FOO_THE_NAMES_0_FIRST": "spring",
            "FOO_THE_NAMES_0_LAST": "boot",
            "FOO_THE_NAMES_1_FIRST": "binding",
            "FOO_THE_NAMES_1_LAST": "test"
        ]);
        assertNames(binderOf!(List!Name)([environment], valueObject!Name(),
                valueObject!BeanWithCamelCaseNameList()).bind!BeanWithCamelCaseNameList("foo").get());
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
