/// Link proof for the Java StringJoiner leaf.
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.stringjoiner : StringJoiner;

@safe:

int main(string[] args)
{
    auto joiner = new StringJoiner(",", "[", "]").setEmptyValue("empty");
    foreach (element; args[1 .. $])
        joiner.add(element);
    joiner.merge(new StringJoiner(":", "<", ">").add("x").add("y"));
    foreach (character; joiner.toString())
        fputc(character, stdout);
    return joiner.length() & 127;
}
