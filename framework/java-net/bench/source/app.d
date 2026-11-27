// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.urldecoder : URLDecoder;
import flint.java.net.urlencoder : URLEncoder;

@safe:

int main(string[] args)
{
    const input = args.length > 1 ? args[1] : "café +";
    const encoded = URLEncoder.encode(input, "UTF-8");
    const decoded = URLDecoder.decode(encoded, "UTF-8");
    return decoded == input ? 0 : 1;
}
