// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module form_encode_probe;

import flint.java.net.urlencoder : URLEncoder;

@safe:

int main(string[] args)
{
    auto value = URLEncoder.encode(args.length > 1 ? args[1] : "a + ü", args.length > 2 ? args[2] : "UTF-16BE");
    return cast(int) value.length & 127;
}
