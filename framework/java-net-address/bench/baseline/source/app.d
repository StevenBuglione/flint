// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    const host = args.length > 1 ? args[1] : "10.0.0.1";
    return cast(int) host.length & 127;
}
