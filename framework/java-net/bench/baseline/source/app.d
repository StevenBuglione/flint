// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    const input = args.length > 1 ? args[1] : "café +";
    return input.ptr is null ? 1 : 0;
}
