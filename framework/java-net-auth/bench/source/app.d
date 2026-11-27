// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.passwordauthentication : PasswordAuthentication;

@safe:

int main(string[] args)
{
    auto auth = new PasswordAuthentication(args[0], "secret"w);
    return cast(int)(auth.getUserName().length + auth.getPassword().length) & 127;
}
