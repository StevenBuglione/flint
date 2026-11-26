module flint.core_io_file_url_test;

import flint.core.io : DefaultResourceLoader, FileSystemResource;
import flint.java.io : FileNotFoundException;
import flint.util : StringUtils;
import std.conv : to;
import std.exception : assertThrown;
import std.file : mkdir, rmdirRecurse, tempDir, write;
import std.path : buildPath;
import std.process : thisProcessID;

@safe:

private string fileUrl(string directory, string escapedName)
{
    const path = StringUtils.replace(directory, "\\", "/");
    version (Windows)
        return "file:///" ~ path ~ "/" ~ escapedName;
    else
        return "file://" ~ path ~ "/" ~ escapedName;
}

@("file URLs decode the local path once and preserve literal plus signs")
unittest
{
    const root = buildPath(tempDir(), "flint-file-url-" ~ thisProcessID.to!string);
    mkdir(root);
    scope (exit)
        rmdirRecurse(root);
    write(buildPath(root, "model weights.txt"), "weights");
    write(buildPath(root, "café#part.txt"), "données");
    write(buildPath(root, "model%20+data.txt"), "escaped once");

    auto loader = new DefaultResourceLoader;
    const weightsUrl = fileUrl(root, "model%20weights.txt");
    auto weights = loader.getResource(weightsUrl);
    assert(cast(FileSystemResource) weights !is null && weights.getContentAsString() == "weights");
    const localhostUrl = "file://localhost" ~ weightsUrl["file://".length .. $];
    assert(loader.getResource(localhostUrl).getContentAsString() == "weights");
    auto delimited = loader.getResource(fileUrl(root, "caf%C3%A9%23part.txt?ignored#fragment"));
    assert(delimited.getFilename() == "café#part.txt" && delimited.getContentAsString() == "données");
    assert(loader.getResource(fileUrl(root, "model%2520+data.txt")).getContentAsString() == "escaped once");
}

@("malformed file URL escapes fall back to the literal path without partial decoding")
unittest
{
    const root = buildPath(tempDir(), "flint-file-url-invalid-" ~ thisProcessID.to!string);
    mkdir(root);
    scope (exit)
        rmdirRecurse(root);
    write(buildPath(root, "literal%20%2G.txt"), "literal");
    write(buildPath(root, "safe.txt"), "prefix");

    auto loader = new DefaultResourceLoader;
    assert(loader.getResource(fileUrl(root, "literal%20%2G.txt")).getContentAsString() == "literal");
    auto nul = loader.getResource(fileUrl(root, "safe.txt%00suffix"));
    assert(!nul.exists());
    assertThrown!FileNotFoundException(nul.getInputStream());
}
