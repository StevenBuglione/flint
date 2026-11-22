module flint_tool.engine.cbuild_test;

import flint_tool.engine.cbuild : TidyFinding, parseTidyLine;
import flint.test : expect;

@safe:

@("clang-tidy findings become project-relative locations")
unittest
{
    TidyFinding finding;
    expect(parseTidyLine("/work/shop/native/crc.c:20:5: warning: Call to function 'strcpy' is insecure "
            ~ "[clang-analyzer-security.insecureAPI.strcpy]", "/work/shop", finding)).toEqual(true);
    expect(finding.file).toEqual("native/crc.c");
    expect(finding.line).toEqual(20);
    expect(finding.column).toEqual(5);
    expect(finding.message).toEqual(
            "Call to function 'strcpy' is insecure [clang-analyzer-security.insecureAPI.strcpy]");
}

@("other clang-tidy output is not a finding")
unittest
{
    TidyFinding finding;
    expect(parseTidyLine("1 warning generated.", "/work/shop", finding)).toEqual(false);
    expect(parseTidyLine("    20 |     strcpy(buffer, \"x\");", "/work/shop", finding)).toEqual(false);
    expect(parseTidyLine("crc.c:x:y: error: bad", "/work/shop", finding)).toEqual(false);
}
