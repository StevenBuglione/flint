// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    const text = "null/1 [null]";
    return cast(int)(text.length + args.length) & 127;
}
