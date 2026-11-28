module app;

import flint.java.util.base64 : Base64;

@safe:

int main(string[] args)
{
    const raw = args.length > 1 ? cast(const(byte)[]) args[1] : cast(const(byte)[]) "foob";
    const text = Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
    const mime = Base64.getMimeEncoder().encode(raw);
    const back = Base64.getUrlDecoder().decode(text);
    const fromMime = Base64.getMimeDecoder().decode(mime);
    if (args.length <= 1 && (text != "Zm9vYg" || cast(const(char)[]) mime != "Zm9vYg=="))
        return 1;
    return back == raw && fromMime == raw ? 0 : 2;
}
