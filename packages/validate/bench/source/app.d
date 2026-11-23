module app;

import flint.validate : Min, Pattern, Violation, validate;
import probe : Receipt, consume, printChecksum, runProbe, verify;

@safe:

private struct Fields8
{
    @Min(1)
    int v000;
    @Min(1)
    int v001;
    @Min(1)
    int v002;
    @Min(1)
    int v003;
    @Min(1)
    int v004;
    @Min(1)
    int v005;
    @Min(1)
    int v006;
    @Min(1)
    int v007;
}

private Fields8 load8(scope const(int)[] data) nothrow @nogc
{
    return Fields8(data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]);
}

private struct Fields32
{
    @Min(1)
    int v000;
    @Min(1)
    int v001;
    @Min(1)
    int v002;
    @Min(1)
    int v003;
    @Min(1)
    int v004;
    @Min(1)
    int v005;
    @Min(1)
    int v006;
    @Min(1)
    int v007;
    @Min(1)
    int v008;
    @Min(1)
    int v009;
    @Min(1)
    int v010;
    @Min(1)
    int v011;
    @Min(1)
    int v012;
    @Min(1)
    int v013;
    @Min(1)
    int v014;
    @Min(1)
    int v015;
    @Min(1)
    int v016;
    @Min(1)
    int v017;
    @Min(1)
    int v018;
    @Min(1)
    int v019;
    @Min(1)
    int v020;
    @Min(1)
    int v021;
    @Min(1)
    int v022;
    @Min(1)
    int v023;
    @Min(1)
    int v024;
    @Min(1)
    int v025;
    @Min(1)
    int v026;
    @Min(1)
    int v027;
    @Min(1)
    int v028;
    @Min(1)
    int v029;
    @Min(1)
    int v030;
    @Min(1)
    int v031;
}

private Fields32 load32(scope const(int)[] data) nothrow @nogc
{
    return Fields32(data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7],
            data[8], data[9], data[10], data[11], data[12], data[13], data[14], data[15], data[16],
            data[17], data[18], data[19], data[20], data[21], data[22], data[23], data[24],
            data[25], data[26], data[27], data[28], data[29], data[30], data[31]);
}

private struct Fields128
{
    @Min(1)
    int v000;
    @Min(1)
    int v001;
    @Min(1)
    int v002;
    @Min(1)
    int v003;
    @Min(1)
    int v004;
    @Min(1)
    int v005;
    @Min(1)
    int v006;
    @Min(1)
    int v007;
    @Min(1)
    int v008;
    @Min(1)
    int v009;
    @Min(1)
    int v010;
    @Min(1)
    int v011;
    @Min(1)
    int v012;
    @Min(1)
    int v013;
    @Min(1)
    int v014;
    @Min(1)
    int v015;
    @Min(1)
    int v016;
    @Min(1)
    int v017;
    @Min(1)
    int v018;
    @Min(1)
    int v019;
    @Min(1)
    int v020;
    @Min(1)
    int v021;
    @Min(1)
    int v022;
    @Min(1)
    int v023;
    @Min(1)
    int v024;
    @Min(1)
    int v025;
    @Min(1)
    int v026;
    @Min(1)
    int v027;
    @Min(1)
    int v028;
    @Min(1)
    int v029;
    @Min(1)
    int v030;
    @Min(1)
    int v031;
    @Min(1)
    int v032;
    @Min(1)
    int v033;
    @Min(1)
    int v034;
    @Min(1)
    int v035;
    @Min(1)
    int v036;
    @Min(1)
    int v037;
    @Min(1)
    int v038;
    @Min(1)
    int v039;
    @Min(1)
    int v040;
    @Min(1)
    int v041;
    @Min(1)
    int v042;
    @Min(1)
    int v043;
    @Min(1)
    int v044;
    @Min(1)
    int v045;
    @Min(1)
    int v046;
    @Min(1)
    int v047;
    @Min(1)
    int v048;
    @Min(1)
    int v049;
    @Min(1)
    int v050;
    @Min(1)
    int v051;
    @Min(1)
    int v052;
    @Min(1)
    int v053;
    @Min(1)
    int v054;
    @Min(1)
    int v055;
    @Min(1)
    int v056;
    @Min(1)
    int v057;
    @Min(1)
    int v058;
    @Min(1)
    int v059;
    @Min(1)
    int v060;
    @Min(1)
    int v061;
    @Min(1)
    int v062;
    @Min(1)
    int v063;
    @Min(1)
    int v064;
    @Min(1)
    int v065;
    @Min(1)
    int v066;
    @Min(1)
    int v067;
    @Min(1)
    int v068;
    @Min(1)
    int v069;
    @Min(1)
    int v070;
    @Min(1)
    int v071;
    @Min(1)
    int v072;
    @Min(1)
    int v073;
    @Min(1)
    int v074;
    @Min(1)
    int v075;
    @Min(1)
    int v076;
    @Min(1)
    int v077;
    @Min(1)
    int v078;
    @Min(1)
    int v079;
    @Min(1)
    int v080;
    @Min(1)
    int v081;
    @Min(1)
    int v082;
    @Min(1)
    int v083;
    @Min(1)
    int v084;
    @Min(1)
    int v085;
    @Min(1)
    int v086;
    @Min(1)
    int v087;
    @Min(1)
    int v088;
    @Min(1)
    int v089;
    @Min(1)
    int v090;
    @Min(1)
    int v091;
    @Min(1)
    int v092;
    @Min(1)
    int v093;
    @Min(1)
    int v094;
    @Min(1)
    int v095;
    @Min(1)
    int v096;
    @Min(1)
    int v097;
    @Min(1)
    int v098;
    @Min(1)
    int v099;
    @Min(1)
    int v100;
    @Min(1)
    int v101;
    @Min(1)
    int v102;
    @Min(1)
    int v103;
    @Min(1)
    int v104;
    @Min(1)
    int v105;
    @Min(1)
    int v106;
    @Min(1)
    int v107;
    @Min(1)
    int v108;
    @Min(1)
    int v109;
    @Min(1)
    int v110;
    @Min(1)
    int v111;
    @Min(1)
    int v112;
    @Min(1)
    int v113;
    @Min(1)
    int v114;
    @Min(1)
    int v115;
    @Min(1)
    int v116;
    @Min(1)
    int v117;
    @Min(1)
    int v118;
    @Min(1)
    int v119;
    @Min(1)
    int v120;
    @Min(1)
    int v121;
    @Min(1)
    int v122;
    @Min(1)
    int v123;
    @Min(1)
    int v124;
    @Min(1)
    int v125;
    @Min(1)
    int v126;
    @Min(1)
    int v127;
}

private Fields128 load128(scope const(int)[] data) nothrow @nogc
{
    return Fields128(data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7],
            data[8], data[9], data[10], data[11], data[12], data[13], data[14], data[15], data[16],
            data[17], data[18], data[19], data[20], data[21], data[22], data[23], data[24],
            data[25], data[26], data[27], data[28], data[29], data[30], data[31], data[32],
            data[33], data[34], data[35], data[36], data[37], data[38], data[39], data[40],
            data[41], data[42], data[43], data[44], data[45], data[46], data[47], data[48],
            data[49], data[50], data[51], data[52], data[53], data[54], data[55], data[56],
            data[57], data[58], data[59], data[60], data[61], data[62], data[63], data[64],
            data[65], data[66], data[67], data[68], data[69], data[70], data[71], data[72],
            data[73], data[74], data[75], data[76], data[77], data[78], data[79], data[80],
            data[81], data[82], data[83], data[84], data[85], data[86], data[87], data[88],
            data[89], data[90], data[91], data[92], data[93], data[94], data[95], data[96],
            data[97], data[98], data[99], data[100], data[101], data[102], data[103], data[104],
            data[105], data[106], data[107], data[108], data[109], data[110], data[111], data[112],
            data[113], data[114], data[115], data[116], data[117], data[118], data[119], data[120],
            data[121], data[122], data[123], data[124], data[125], data[126], data[127]);
}

pragma(inline, false) private Receipt runDto(alias load, size_t width)(scope const(int)[] data, bool full) nothrow @nogc
{
    const dto = load(data);
    if (!full)
    {
        const counted = validate(dto, []);
        return Receipt(counted.total, counted.written, counted.valid, 0);
    }

    Violation[width] output;
    const observed = validate(dto, output[]);
    ulong digest;
    foreach (ref const violation; output[0 .. observed.written])
        digest = consume(digest, violation.field, violation.constraint);
    return Receipt(observed.total, observed.written, observed.valid, digest);
}

pragma(inline, false) private bool patternTrial(scope const(char)[] data) nothrow @nogc
{
    struct Expression
    {
        @Pattern("(a+)+b")
        const(char)[] value;
    }

    scope dto = Expression(data);
    return validate(dto, []).valid;
}

void main(string[] args)
{
    verify(args.length == 1 || (args.length == 2 && args[1] == "--measure"));
    const checksum = runProbe([
        &runDto!(load8, 8), &runDto!(load32, 32), &runDto!(load128, 128)
    ], &patternTrial, args.length == 2);
    printChecksum(checksum);
}
