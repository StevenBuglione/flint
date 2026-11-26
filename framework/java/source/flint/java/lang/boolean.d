module flint.java.lang.boolean;
@safe:
/// Java's `Boolean` statics.
struct Boolean
{
    /// `true` exactly when `s` equals `"true"`, ignoring case; anything else, null included, is false.
    static bool parseBoolean(string s) pure nothrow @nogc
    {
        if (s.length != 4)
            return false;
        foreach (i, c; "true")
            if ((s[i] | 0x20) != c)
                return false;
        return true;
    }

    /// `"true"` or `"false"`.
    static string toString(bool b) pure nothrow @nogc
    {
        return b ? "true" : "false";
    }

    /// Java's `Boolean.hashCode(boolean)`: 1231 or 1237.
    static int hashCode(bool value) pure nothrow @nogc
    {
        return value ? 1231 : 1237;
    }
}
