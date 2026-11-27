// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.httpcookie : HttpCookie;

@safe:

int main(string[] args)
{
    const header = args.length > 1
        ? args[1] : "Set-Cookie: session=value; Path=/web; Domain=example.com; Max-Age=60; HttpOnly";
    auto cookies = HttpCookie.parse(header);
    if (cookies.size() == 0)
        return 1;
    auto cookie = cookies.get(0);
    return HttpCookie.domainMatches(cookie.getDomain().get, "example.com") && !cookie.hasExpired() ? 0 : 1;
}
