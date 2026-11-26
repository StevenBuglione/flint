// Ported from spring-framework v7.1.0: spring-beans/src/main/java/org/springframework/beans/PropertyMatches.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.beans.propertymatches;

import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : NullPointerException;
import flint.java.util : stableSort;

@safe:

/// Likely alternatives for a bean property or field name.
abstract class PropertyMatches
{
    /// Java's default maximum edit distance.
    enum int DEFAULT_MAX_DISTANCE = 2;

    private string propertyName;
    private string[] matches;

    private this(string propertyName, string[] matches)
    {
        this.propertyName = propertyName;
        this.matches = matches;
    }

    /// Match writable properties from the AOT descriptor for `T` (R4).
    static PropertyMatches forProperty(T)(string propertyName, int maxDistance = DEFAULT_MAX_DISTANCE)
    {
        string[] names;
        foreach (ref property; descriptorOf!T().properties)
        {
            if (property.set !is null)
                names ~= property.name;
        }
        return forProperty(propertyName, names, maxDistance);
    }

    /// Match the fields of `T` from compile-time field metadata (R4).
    static PropertyMatches forField(T)(string propertyName, int maxDistance = DEFAULT_MAX_DISTANCE)
    {
        return forField(propertyName, fieldNames!T, maxDistance);
    }

    /// Flint addition for matching an explicit set of writable property names.
    static PropertyMatches forProperty(string propertyName, scope const(string)[] names,
            int maxDistance = DEFAULT_MAX_DISTANCE)
    {
        return new Matches(propertyName, findMatches(propertyName, names, maxDistance), false);
    }

    /// Flint addition for matching an explicit set of field names.
    static PropertyMatches forField(string propertyName, scope const(string)[] names,
            int maxDistance = DEFAULT_MAX_DISTANCE)
    {
        return new Matches(propertyName, findMatches(propertyName, names, maxDistance), true);
    }

    /// The name that failed to bind.
    string getPropertyName()
    {
        return propertyName;
    }

    /// The possible replacements in Java string order.
    string[] getPossibleMatches()
    {
        return matches;
    }

    /// Render the Java property or field error and any hints.
    abstract string buildErrorMessage();

    /// Append the possible matches to a message (D-BEANS-1).
    protected void appendHintMessage(ref string message)
    {
        message ~= "Did you mean ";
        foreach (i, match; matches)
        {
            if (i != 0)
                message ~= i + 1 == matches.length ? ", or " : ", ";
            message ~= "'" ~ match ~ "'";
        }
        message ~= "?";
    }
}

private final class Matches : PropertyMatches
{
    private const bool field;

    this(string propertyName, string[] matches, bool field)
    {
        super(propertyName, matches);
        this.field = field;
    }

    override string buildErrorMessage()
    {
        string message = "Bean property '" ~ getPropertyName() ~ "'";
        if (field)
        {
            message ~= " has no matching field.";
            if (getPossibleMatches().length)
            {
                message ~= " ";
                appendHintMessage(message);
            }
            return message;
        }

        message ~= " is not writable or has an invalid setter method. ";
        if (getPossibleMatches().length)
            appendHintMessage(message);
        else
            message ~= "Does the parameter type of the setter match the return type of the getter?";
        return message;
    }
}

private template fieldNames(T)
{
    private string[] collect()
    {
        string[] names;
        static foreach (i; 0 .. T.tupleof.length)
            names ~= __traits(identifier, T.tupleof[i]);
        static if (is(T == class) && !is(T == Object) && is(T Bases == super))
        {
            static if (Bases.length && is(Bases[0] == class))
                names ~= fieldNames!(Bases[0]);
        }
        return names;
    }

    enum fieldNames = collect();
}

private struct Candidate
{
    string name;
    wchar[] units;
}

private string[] findMatches(string property, scope const(string)[] names, int maxDistance)
{
    if (property is null)
        throw new NullPointerException("Property name must not be null");
    if (maxDistance < 0)
        return null;

    auto requested = utf16(property);
    auto row = new size_t[requested.length + 1];
    Candidate[] matches;
    foreach (name; names)
    {
        auto units = utf16(name);
        auto difference = requested.length > units.length ? requested.length - units.length
            : units.length - requested.length;
        if (difference <= maxDistance && distance(requested, units, row) <= maxDistance)
            matches ~= Candidate(name, units);
    }
    stableSort!Candidate(matches, (Candidate a, Candidate b) => a.units < b.units ? -1 : (b.units < a.units ? 1 : 0));
    auto result = new string[matches.length];
    foreach (i, match; matches)
        result[i] = match.name;
    return result;
}

private wchar[] utf16(string text)
{
    auto result = new wchar[text.length];
    size_t count;
    for (size_t index; index < text.length;)
    {
        auto codePoint = decodeUtf8(text, index);
        if (codePoint <= 0xFFFF)
        {
            result[count++] = cast(wchar) codePoint;
        }
        else
        {
            codePoint -= 0x10000;
            result[count++] = cast(wchar)(0xD800 | (codePoint >> 10));
            result[count++] = cast(wchar)(0xDC00 | (codePoint & 0x3FF));
        }
    }
    return result[0 .. count];
}

// One row is enough: retain the old diagonal while writing the current row.
private size_t distance(scope const(wchar)[] needle, scope const(wchar)[] candidate, scope size_t[] row) nothrow @nogc
{
    foreach (i, ref item; row)
        item = i;
    foreach (i, element; candidate)
    {
        size_t diagonal = row[0];
        row[0] = i + 1;
        foreach (j, sought; needle)
        {
            const above = row[j + 1];
            const remove = above + 1;
            const insert = row[j] + 1;
            const replace = diagonal + (element != sought);
            const nearest = insert < remove ? insert : remove;
            row[j + 1] = replace < nearest ? replace : nearest;
            diagonal = above;
        }
    }
    return row[$ - 1];
}
