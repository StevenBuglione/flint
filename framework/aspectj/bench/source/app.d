/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: EPL-2.0
 */
module app;

import core.stdc.stdio : fputc, stdout;
import flint.aspectj.lang.annotation : Around;
import std.traits : getUDAs;

@safe:

@Around("execution(* *.rename(..))", "name")
private void rename(string)
{
}

int main(string[] args)
{
    enum advice = getUDAs!(rename, Around)[0];
    foreach (character; args.length > 1 ? advice.argNames : advice.value)
        fputc(character, stdout);
    fputc('\n', stdout);
    return 0;
}
