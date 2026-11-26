// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    auto input = args.length > 1 ? args[1] : "";
    return cast(int)(input.length & 127);
}
