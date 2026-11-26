/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: EPL-2.0
 */
module app;

import core.stdc.stdio : fputc, stdout;

@safe:

int main(string[] args)
{
    foreach (character; args.length > 1 ? "name" : "execution(* *.rename(..))")
        fputc(character, stdout);
    fputc('\n', stdout);
    return 0;
}
