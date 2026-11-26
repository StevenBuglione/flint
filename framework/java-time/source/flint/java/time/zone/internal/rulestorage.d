/// Internal storage contract for rules built from explicit transitions.
module flint.java.time.zone.internal.rulestorage;

import flint.java.time : Instant, LocalDateTime, ZoneOffset;
import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule;

@safe:

// Supplied rules bind their storage only when the transition-list factory is used.
package(flint.java.time.zone) interface RuleStorage
{
    bool hasWallChanges() const pure nothrow @nogc;
    bool hasStandardChanges() const pure nothrow @nogc;
    ZoneOffset offsetAt(Instant instant) const;
    ZoneOffset standardAt(Instant instant) const pure nothrow @nogc;
    LocalMatch localAt(LocalDateTime dateTime) const;
    LocalMatch next(Instant instant) const;
    LocalMatch previous(Instant instant) const;
    size_t historicCount() const pure nothrow @nogc;
    LocalMatch historic(size_t index) const;
    immutable(ZoneOffsetTransitionRule)[] annual() const pure nothrow @nogc;
    bool same(const RuleStorage other) const pure nothrow @nogc;
    int hash() const pure nothrow @nogc;
    ZoneOffset finalStandard() const pure nothrow @nogc;
}

package(flint.java.time.zone) struct LocalMatch
{
    ZoneOffset offset;
    ZoneOffset after;
    LocalDateTime beforeTime;
    bool transitioning;
}
