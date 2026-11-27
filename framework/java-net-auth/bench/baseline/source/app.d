// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

@safe:

int main(string[] args)
{
    auto password = "secret"w.dup;
    return cast(int)(args[0].length + password.length) & 127;
}
