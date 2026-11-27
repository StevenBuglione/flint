// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    const message = args.length > 0 ? args[0] : "unknown";
    return cast(int) message.length & 127;
}
