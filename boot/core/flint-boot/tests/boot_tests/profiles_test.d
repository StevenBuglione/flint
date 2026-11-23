// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// ProfilesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Flint computes `Profiles` while loading config data, so each test runs a
// `ConfigDataEnvironment` with no files: a MockEnvironment property is a command-line argument, a property only the
// Binder sees is a (lower-precedence) default property, `environment.setActiveProfiles` is the programmatic
// additional profiles, and `environment.setDefaultProfiles` without a competing property is
// `spring.profiles.default`; iterating a `Profiles` is `getAccepted()`.
module boot_tests.profiles_test;

import boot_tests.upstream_support : MemoryReader;
import flint.boot.context.config : ConfigDataEnvironment, ConfigDataEnvironmentOptions, Profiles;

@safe:

/// The profiles of a run whose environment holds `environment` (command line), whose Binder also sees `binder`
/// (default properties), with `additional` programmatic profiles.
private Profiles profiles(string[2][] environment, string[2][] binder = null, string[] additional = null)
{
    ConfigDataEnvironmentOptions options;
    foreach (property; environment)
        options.args ~= "--" ~ property[0] ~ "=" ~ property[1];
    foreach (property; binder)
        options.defaultProperties[property[0]] = property[1];
    options.additionalProfiles = additional;
    options.reader = new MemoryReader(null);
    return new ConfigDataEnvironment(options).processAndApply().getProfiles();
}

@("getActiveWhenNoEnvironmentProfilesAndNoPropertyReturnsEmptyArray") unittest
{
    assert(profiles(null).getActive().length == 0);
}

@("getActiveWhenNoEnvironmentProfilesAndBinderProperty") unittest
{
    assert(profiles(null, [["spring.profiles.active", "a,b,c"]]).getActive() == ["a", "b", "c"]);
}

@("getActiveWhenNoEnvironmentProfilesAndEnvironmentProperty") unittest
{
    assert(profiles([["spring.profiles.active", "a,b,c"]]).getActive() == ["a", "b", "c"]);
}

@("getActiveWhenEnvironmentProfilesAndBinderProperty") unittest
{
    const active = profiles(null, [["spring.profiles.active", "d,e,f"]], ["a", "b", "c"]).getActive();
    assert(active == ["a", "b", "c", "d", "e", "f"]);
}

@("getActiveWhenEnvironmentProfilesAndBinderPropertyShouldReturnEnvironmentProperty") unittest
{
    const active = profiles([["spring.profiles.active", "a,b,c"]], [
        ["spring.profiles.active", "d,e,f"]
    ]).getActive();
    assert(active == ["a", "b", "c"]);
}

@("getActiveWhenEnvironmentProfilesAndEnvironmentProperty") unittest
{
    const active = profiles([["spring.profiles.active", "d,e,f"]], null, ["a", "b", "c"]).getActive();
    assert(active == ["a", "b", "c", "d", "e", "f"]);
}

@("getActiveWhenNoEnvironmentProfilesAndEnvironmentPropertyInBindNotation") unittest
{
    const active = profiles([
        ["spring.profiles.active[0]", "a"], ["spring.profiles.active[1]", "b"],
        ["spring.profiles.active[2]", "c"]
    ]).getActive();
    assert(active == ["a", "b", "c"]);
}

@("getActiveWhenEnvironmentProfilesInBindNotationAndEnvironmentPropertyReturnsEnvironmentProfiles") unittest
{
    const active = profiles([
        ["spring.profiles.active[0]", "d"], ["spring.profiles.active[1]", "e"],
        ["spring.profiles.active[2]", "f"]
    ], null, ["a", "b", "c"]).getActive();
    assert(active == ["a", "b", "c", "d", "e", "f"]);
}

@("getActiveWhenHasDuplicatesReturnsUniqueElements") unittest
{
    assert(profiles([["spring.profiles.active", "a,b,a,b,c"]]).getActive() == ["a", "b", "c"]);
}

@("getActiveWithProfileGroups") unittest
{
    const active = profiles([
        ["spring.profiles.active", "a,b,c"], ["spring.profiles.group.a", "d,e"]
    ]).getActive();
    assert(active == ["a", "d", "e", "b", "c"]);
}

@("getActiveWhenHasAdditionalIncludesAdditional") unittest
{
    const active = profiles([["spring.profiles.active", "d,e,f"]], null, ["a", "b", "c"]).getActive();
    assert(active == ["a", "b", "c", "d", "e", "f"]);
}

@("getDefaultWhenNoEnvironmentProfilesAndNoPropertyReturnsEmptyArray") unittest
{
    assert(profiles(null).getDefault() == ["default"]);
}

@("getDefaultWhenNoEnvironmentProfilesAndBinderProperty") unittest
{
    assert(profiles(null, [["spring.profiles.default", "a,b,c"]]).getDefault() == ["a", "b", "c"]);
}

@("getDefaultWhenDefaultEnvironmentProfileAndBinderProperty") unittest
{
    const defaults = profiles([["spring.profiles.default", "default"]], [
        ["spring.profiles.default", "a,b,c"]
    ]).getDefault();
    assert(defaults == ["default"]);
}

@("getDefaultWhenNoEnvironmentProfilesAndEnvironmentProperty") unittest
{
    assert(profiles([["spring.profiles.default", "a,b,c"]]).getDefault() == ["a", "b", "c"]);
}

version (FlintProgrammaticDefaultProfiles)
{
    // Gap: there are no programmatic default profiles (Environment.setDefaultProfiles) that win over the
    // `spring.profiles.default` property.
    private Profiles withDefaultProfiles(string[] defaults, string[2][] environment, string[2][] binder = null)
    {
        ConfigDataEnvironmentOptions options;
        foreach (property; environment)
            options.args ~= "--" ~ property[0] ~ "=" ~ property[1];
        foreach (property; binder)
            options.defaultProperties[property[0]] = property[1];
        options.defaultProfiles = defaults;
        options.reader = new MemoryReader(null);
        return new ConfigDataEnvironment(options).processAndApply().getProfiles();
    }

    @("getDefaultWhenEnvironmentProfilesAndBinderProperty") unittest
    {
        const defaults = withDefaultProfiles(["a", "b", "c"], null, [
            ["spring.profiles.default", "d,e,f"]
        ]).getDefault();
        assert(defaults == ["a", "b", "c"]);
    }

    @("getDefaultWhenEnvironmentProfilesAndEnvironmentProperty") unittest
    {
        const defaults = withDefaultProfiles(["a", "b", "c"], [["spring.profiles.default", "d,e,f"]]).getDefault();
        assert(defaults == ["a", "b", "c"]);
    }

    @("getDefaultWhenEnvironmentProfilesInBindNotationAndEnvironmentPropertyReturnsBoth") unittest
    {
        const defaults = withDefaultProfiles(["a", "b", "c"], [
            ["spring.profiles.default[0]", "d"], ["spring.profiles.default[1]", "e"],
            ["spring.profiles.default[2]", "f"]
        ]).getDefault();
        assert(defaults == ["a", "b", "c"]);
    }
}

@("getDefaultWhenNoEnvironmentProfilesAndEnvironmentPropertyInBindNotation") unittest
{
    const defaults = profiles([
        ["spring.profiles.default[0]", "a"], ["spring.profiles.default[1]", "b"],
        ["spring.profiles.default[2]", "c"]
    ]).getDefault();
    assert(defaults == ["a", "b", "c"]);
}

@("getDefaultWhenHasDuplicatesReturnsUniqueElements") unittest
{
    assert(profiles([["spring.profiles.default", "a,b,a,b,c"]]).getDefault() == ["a", "b", "c"]);
}

@("getDefaultWithProfileGroups") unittest
{
    const defaults = profiles([
        ["spring.profiles.default", "a,b,c"], ["spring.profiles.group.a", "d,e"]
    ]).getDefault();
    assert(defaults == ["a", "d", "e", "b", "c"]);
}

@("iteratorIteratesAllActiveProfiles") unittest
{
    const accepted = profiles([["spring.profiles.default", "d,e,f"]], null, ["a", "b", "c"]).getAccepted();
    assert(accepted == ["a", "b", "c"]);
}

@("iteratorIteratesAllDefaultProfilesWhenNoActive") unittest
{
    assert(profiles([["spring.profiles.default", "d,e,f"]]).getAccepted() == ["d", "e", "f"]);
}

@("isActiveWhenActiveContainsProfileReturnsTrue") unittest
{
    assert(profiles(null, null, ["a", "b", "c"]).isAccepted("a"));
}

@("isActiveWhenActiveDoesNotContainProfileReturnsFalse") unittest
{
    assert(!profiles(null, null, ["a", "b", "c"]).isAccepted("x"));
}

@("isActiveWhenNoActiveAndDefaultContainsProfileReturnsTrue") unittest
{
    assert(profiles([["spring.profiles.default", "d,e,f"]]).isAccepted("d"));
}

@("isActiveWhenNoActiveAndDefaultDoesNotContainProfileReturnsFalse") unittest
{
    assert(!profiles([["spring.profiles.default", "d,e,f"]]).isAccepted("x"));
}

@("iteratorWithProfileGroups") unittest
{
    const accepted = profiles([
        ["spring.profiles.active", "a,b,c"], ["spring.profiles.group.a", "e,f"],
        ["spring.profiles.group.e", "x,y"]
    ]).getAccepted();
    assert(accepted == ["a", "e", "x", "y", "f", "b", "c"]);
}

@("iteratorWithProfileGroupsAndNoActive") unittest
{
    const accepted = profiles([
        ["spring.profiles.group.a", "e,f"], ["spring.profiles.group.e", "x,y"]
    ]).getAccepted();
    assert(accepted == ["default"]);
}

@("iteratorWithProfileGroupsForDefault") unittest
{
    assert(profiles([["spring.profiles.group.default", "e,f"]]).getAccepted() == [
        "default", "e", "f"
    ]);
}

@("getAcceptedWithProfileGroups") unittest
{
    const accepted = profiles([
        ["spring.profiles.active", "a,b,c"], ["spring.profiles.group.a", "e,f"],
        ["spring.profiles.group.e", "x,y"], ["spring.profiles.default", "g,h,i"]
    ]).getAccepted();
    assert(accepted == ["a", "e", "x", "y", "f", "b", "c"]);
}

@("getAcceptedWhenNoActiveAndDefaultWithGroups") unittest
{
    const accepted = profiles([
        ["spring.profiles.default", "d,e,f"], ["spring.profiles.group.e", "x,y"]
    ]).getAccepted();
    assert(accepted == ["d", "e", "x", "y", "f"]);
}

@("isAcceptedWithGroupsReturnsTrue") unittest
{
    auto p = profiles([
        ["spring.profiles.active", "a,b,c"], ["spring.profiles.group.a", "e,f"],
        ["spring.profiles.group.e", "x,y"], ["spring.profiles.default", "g,h,i"]
    ]);
    assert(p.isAccepted("a"));
    assert(p.isAccepted("e"));
    assert(!p.isAccepted("g"));
}

@("isAcceptedWhenNoActiveAndDefaultWithGroupsContainsProfileReturnsTrue") unittest
{
    auto p = profiles([["spring.profiles.default", "d,e,f"], ["spring.profiles.group.e", "x,y"]]);
    assert(p.isAccepted("d"));
    assert(p.isAccepted("x"));
}

@("simpleRecursiveReferenceInProfileGroupIgnoresDuplicates") unittest
{
    const accepted = profiles([
        ["spring.profiles.active", "a,b,c"], ["spring.profiles.group.a", "a,e,f"]
    ]).getAccepted();
    assert(accepted == ["a", "e", "f", "b", "c"]);
}

@("multipleRecursiveReferenceInProfileGroupIgnoresDuplicates") unittest
{
    const accepted = profiles([
        ["spring.profiles.active", "a,b,c"], ["spring.profiles.group.a", "a,b,f"]
    ]).getAccepted();
    assert(accepted == ["a", "b", "f", "c"]);
}

@("complexRecursiveReferenceInProfileGroupIgnoresDuplicates") unittest
{
    const accepted = profiles([
        ["spring.profiles.active", "a,b,c"], ["spring.profiles.group.a", "e,f,g"],
        ["spring.profiles.group.e", "a,x,y,g"]
    ]).getAccepted();
    assert(accepted == ["a", "e", "x", "y", "g", "f", "b", "c"]);
}

@("validNamesArePermitted") unittest
{
    profiles([["spring.profiles.active", "ok"]]);
    profiles([["spring.profiles.default", "ok"]]);
    profiles([["spring.profiles.group.a", "ok"]]);
}

@("invalidNamesWhenValidationDisabledArePermitted") unittest
{
    const accepted = profiles([
        ["spring.profiles.validate", "false"], ["spring.profiles.active", "fa!l"]
    ]).getAccepted();
    assert(accepted == ["fa!l"]);
}

version (FlintProfileNameValidation)
{
    // Gap: profile names are not validated (`spring.profiles.validate`), so `fa!l` is accepted.
    import boot_tests.support : assertThrows;
    import flint.java.lang : IllegalStateException, RuntimeException;

    @("invalidNamesAreNotPermitted") unittest
    {
        assertThrows!RuntimeException(() { profiles([["spring.profiles.active", "fa!l"]]); });
        assertThrows!RuntimeException(() { profiles([["spring.profiles.default", "fa!l"]]); });
        assertThrows!RuntimeException(() { profiles([["spring.profiles.group.a", "fa!l"]]); });
    }

    @("invalidNameInEnvironment") unittest
    {
        assertThrows!IllegalStateException(() { profiles([["spring.profiles.active", "fa!l"]]); },
                "Invalid profile property value found in Environment under 'spring.profiles.active'");
    }

    @("invalidNameInActive") unittest
    {
        assertThrows!IllegalStateException(() { profiles(null, null, ["fa!l"]); },
                "Invalid profile property value found in additional profiles");
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
