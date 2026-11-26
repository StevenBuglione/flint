module app;

import flint.java.util.regex.matchresult : MatchResult;
import std.typecons : Nullable;

@safe:

private final class Sample : MatchResult
{
    private string capture;

    this(string capture)
    {
        this.capture = capture;
    }

    override int start() const
    {
        return 0;
    }

    override int start(int index) const
    {
        return index == 0 ? start() : -1;
    }

    override int end() const
    {
        return cast(int) capture.length;
    }

    override int end(int index) const
    {
        return index == 0 ? end() : -1;
    }

    override Nullable!string group() const
    {
        return Nullable!string(capture);
    }

    override Nullable!string group(int index) const
    {
        return index == 0 ? group() : Nullable!string.init;
    }

    override int groupCount() const
    {
        return 0;
    }
}

int main(string[] args)
{
    const input = args.length > 1 ? args[1] : "result";
    const MatchResult match = new Sample(input);
    return match.start(0) == 0 && match.end() == input.length && match.group(0).get == input ? 0 : 1;
}
