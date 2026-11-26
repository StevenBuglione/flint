// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    const message = args.length > 1 ? args[1] : "unknown";
    return cast(int) message.length & 127;
}
