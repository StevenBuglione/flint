// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module password_authentication_probe;

import flint.java.net.passwordauthentication : PasswordAuthentication;

@safe:

int main(string[] args)
{
    wchar[] secret = ['s', 'e', 'c', 'r', 'e', 't'];
    auto auth = new PasswordAuthentication(args[0], secret);
    secret[0] = 'S';
    auto stored = auth.getPassword();
    stored[] = '\0';
    return auth.getUserName().length > 0 && auth.getPassword()[0] == '\0' ? 0 : 1;
}
