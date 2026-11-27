/** Charset-name lookup for the Java form codec overloads. */
module flint.java.net.internal.formcharsetname;

import flint.java.io.unsupportedencodingexception : UnsupportedEncodingException;
import flint.java.lang : IllegalArgumentException;
import flint.java.nio.charset : Charset;

@safe:

package(flint.java.net):

Charset formCharsetForName(string name, string emptyMessage) pure
{
    if (name.length == 0)
        throw new UnsupportedEncodingException(emptyMessage);
    try
        return Charset.forName(name);
    catch (IllegalArgumentException)
        throw new UnsupportedEncodingException(name);
}
