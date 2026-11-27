// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module form_decode_probe;

import flint.java.net.urldecoder : URLDecoder;

@safe:

int main(string[] args)
{
    auto value = URLDecoder.decode(args.length > 1 ? args[1] : "%00%FC+", args.length > 2 ? args[2] : "UTF-16BE");
    return cast(int) value.length & 127;
}
