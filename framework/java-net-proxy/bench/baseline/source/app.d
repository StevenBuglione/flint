// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    const message = "type HTTP is not compatible with address null";
    return cast(int)(message.length + args.length) & 127;
}
