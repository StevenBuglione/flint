// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    auto buf = new byte[16];
    return cast(int)(buf.length + args.length + 1) & 127;
}
