// Ported from spring-framework v7.1.0: spring-beans/src/test/java/org/springframework/beans/PropertyMatchesTests.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module property_matches_tests;

import flint.beans.propertymatches : PropertyMatches;
import std.string : indexOf;

@safe:

private final class SampleBeanProperties
{
    private string name;
    private string description;
    private int counter1;
    private int counter2;
    private int counter3;

    string getName()
    {
        return name;
    }

    void setName(string value)
    {
        name = value;
    }

    string getDescription()
    {
        return description;
    }

    void setDescription(string value)
    {
        description = value;
    }

    int getCounter1()
    {
        return counter1;
    }

    void setCounter1(int value)
    {
        counter1 = value;
    }

    int getCounter2()
    {
        return counter2;
    }

    void setCounter2(int value)
    {
        counter2 = value;
    }

    int getCounter3()
    {
        return counter3;
    }

    void setCounter3(int value)
    {
        counter3 = value;
    }

    int getReadOnly()
    {
        return 0;
    }
}

private final class SampleFieldProperties
{
    private string name;
    private string description;
    private int counter1;
    private int counter2;
    private int counter3;

    int getComputed()
    {
        return 0;
    }
}

@("simpleBeanPropertyTypo")
unittest
{
    auto matches = PropertyMatches.forProperty!SampleBeanProperties("naem");
    assert(matches.getPossibleMatches() == ["name"]);
}

@("complexBeanPropertyTypo")
unittest
{
    assert(!PropertyMatches.forProperty!SampleBeanProperties("desriptn").getPossibleMatches().length);
}

@("unknownBeanProperty")
unittest
{
    assert(!PropertyMatches.forProperty!SampleBeanProperties("unknown").getPossibleMatches().length);
}

@("severalMatchesBeanProperty")
unittest
{
    auto matches = PropertyMatches.forProperty!SampleBeanProperties("counter");
    assert(matches.getPossibleMatches() == ["counter1", "counter2", "counter3"]);
}

@("simpleBeanPropertyErrorMessage")
unittest
{
    auto matches = PropertyMatches.forProperty!SampleBeanProperties("naem");
    auto message = matches.buildErrorMessage();
    assert(message.indexOf("naem") >= 0 && message.indexOf("name") >= 0);
    assert(message.indexOf("setter") >= 0 && message.indexOf("field") < 0);
}

@("complexBeanPropertyErrorMessage")
unittest
{
    auto matches = PropertyMatches.forProperty!SampleBeanProperties("counter");
    auto message = matches.buildErrorMessage();
    assert(message.indexOf("counter") >= 0);
    assert(message.indexOf("Did you mean 'counter1', 'counter2', or 'counter3'?") >= 0);
}

@("simpleFieldPropertyTypo")
unittest
{
    auto matches = PropertyMatches.forField!SampleFieldProperties("naem");
    assert(matches.getPossibleMatches() == ["name"]);
}

@("complexFieldPropertyTypo")
unittest
{
    assert(!PropertyMatches.forField!SampleFieldProperties("desriptn").getPossibleMatches().length);
}

@("unknownFieldProperty")
unittest
{
    assert(!PropertyMatches.forField!SampleFieldProperties("unknown").getPossibleMatches().length);
}

@("severalMatchesFieldProperty")
unittest
{
    auto matches = PropertyMatches.forField!SampleFieldProperties("counter");
    assert(matches.getPossibleMatches() == ["counter1", "counter2", "counter3"]);
}

@("simpleFieldPropertyErrorMessage")
unittest
{
    auto matches = PropertyMatches.forField!SampleFieldProperties("naem");
    auto message = matches.buildErrorMessage();
    assert(message.indexOf("naem") >= 0 && message.indexOf("name") >= 0);
    assert(message.indexOf("field") >= 0 && message.indexOf("setter") < 0);
}

@("complexFieldPropertyErrorMessage")
unittest
{
    auto matches = PropertyMatches.forField!SampleFieldProperties("counter");
    auto message = matches.buildErrorMessage();
    assert(message.indexOf("counter") >= 0);
    assert(message.indexOf("Did you mean 'counter1', 'counter2', or 'counter3'?") >= 0);
}

@("Bean and field factories use different candidate names")
unittest
{
    assert(!PropertyMatches.forProperty!SampleBeanProperties("readOnly", 0).getPossibleMatches().length);
    assert(!PropertyMatches.forField!SampleFieldProperties("computed", 0).getPossibleMatches().length);
}

@("Distance uses Java UTF-16 units")
unittest
{
    auto matches = PropertyMatches.forField("x", ["\U0001D504"], 2);
    assert(matches.getPossibleMatches() == ["\U0001D504"]);
    assert(!PropertyMatches.forField("x", ["\U0001D504"], 1).getPossibleMatches().length);
}

@("Field suggestions include each inherited field once")
unittest
{
    static class Parent
    {
        private string inherited;
    }

    static final class Child : Parent
    {
        private string local;
    }

    assert(PropertyMatches.forField!Child("inherited", 0).getPossibleMatches() == ["inherited"]);
}

@("Suggestions sort in Java UTF-16 order")
unittest
{
    auto matches = PropertyMatches.forField("x", ["\uE000", "\U0001D504"], 2);
    assert(matches.getPossibleMatches() == ["\U0001D504", "\uE000"]);
}
