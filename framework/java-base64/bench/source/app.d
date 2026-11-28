// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : printf;
import flint.java.util.base64 : Base64;

@safe:

int main() @system
{
    const raw = cast(const(byte)[]) "foobar";
    const text = Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
    const back = Base64.getUrlDecoder().decode(text);
    printf("%d %c\n", cast(int) text.length, back[0]);
    return back.length == raw.length ? 0 : 1;
}
