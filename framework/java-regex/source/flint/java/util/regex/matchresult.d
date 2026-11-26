/// Java SE 21 numbered regular-expression match results.
module flint.java.util.regex.matchresult;

import std.typecons : Nullable;

@safe:

/// Capture state from a successful match. Offsets count UTF-16 code units.
interface MatchResult
{
    int start() const;
    int start(int group) const;
    int end() const;
    int end(int group) const;
    Nullable!string group() const;
    Nullable!string group(int group) const;
    int groupCount() const;
}
