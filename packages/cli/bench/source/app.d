module app;

import flint.cli : Command, Option, parse;
import flint.arena : Status;
import probe : check, printChecksum, runProbe;

@safe:

version (FlintCliScale)
{
    @Command("fixture-10", "CLI metadata fixture")
    private struct Fields10
    {
        @Option("option-000", '\0', "Fixture input")
        int option000;
        @Option("option-001", '\0', "Fixture input")
        int option001;
        @Option("option-002", '\0', "Fixture input")
        int option002;
        @Option("option-003", '\0', "Fixture input")
        int option003;
        @Option("option-004", '\0', "Fixture input")
        int option004;
        @Option("option-005", '\0', "Fixture input")
        int option005;
        @Option("option-006", '\0', "Fixture input")
        int option006;
        @Option("option-007", '\0', "Fixture input")
        int option007;
        @Option("option-008", '\0', "Fixture input")
        int option008;
        @Option("option-009", '\0', "Fixture input")
        int option009;
    }

    private long checksum(scope ref const Fields10 fields) pure nothrow @nogc
    {
        long sum;
        sum += fields.option000;
        sum += fields.option001;
        sum += fields.option002;
        sum += fields.option003;
        sum += fields.option004;
        sum += fields.option005;
        sum += fields.option006;
        sum += fields.option007;
        sum += fields.option008;
        sum += fields.option009;
        return sum;
    }
}

@Command("fixture-64", "CLI metadata fixture")
private struct Fields64
{
    @Option("option-000", '\0', "Fixture input")
    int option000;
    @Option("option-001", '\0', "Fixture input")
    int option001;
    @Option("option-002", '\0', "Fixture input")
    int option002;
    @Option("option-003", '\0', "Fixture input")
    int option003;
    @Option("option-004", '\0', "Fixture input")
    int option004;
    @Option("option-005", '\0', "Fixture input")
    int option005;
    @Option("option-006", '\0', "Fixture input")
    int option006;
    @Option("option-007", '\0', "Fixture input")
    int option007;
    @Option("option-008", '\0', "Fixture input")
    int option008;
    @Option("option-009", '\0', "Fixture input")
    int option009;
    @Option("option-010", '\0', "Fixture input")
    int option010;
    @Option("option-011", '\0', "Fixture input")
    int option011;
    @Option("option-012", '\0', "Fixture input")
    int option012;
    @Option("option-013", '\0', "Fixture input")
    int option013;
    @Option("option-014", '\0', "Fixture input")
    int option014;
    @Option("option-015", '\0', "Fixture input")
    int option015;
    @Option("option-016", '\0', "Fixture input")
    int option016;
    @Option("option-017", '\0', "Fixture input")
    int option017;
    @Option("option-018", '\0', "Fixture input")
    int option018;
    @Option("option-019", '\0', "Fixture input")
    int option019;
    @Option("option-020", '\0', "Fixture input")
    int option020;
    @Option("option-021", '\0', "Fixture input")
    int option021;
    @Option("option-022", '\0', "Fixture input")
    int option022;
    @Option("option-023", '\0', "Fixture input")
    int option023;
    @Option("option-024", '\0', "Fixture input")
    int option024;
    @Option("option-025", '\0', "Fixture input")
    int option025;
    @Option("option-026", '\0', "Fixture input")
    int option026;
    @Option("option-027", '\0', "Fixture input")
    int option027;
    @Option("option-028", '\0', "Fixture input")
    int option028;
    @Option("option-029", '\0', "Fixture input")
    int option029;
    @Option("option-030", '\0', "Fixture input")
    int option030;
    @Option("option-031", '\0', "Fixture input")
    int option031;
    @Option("option-032", '\0', "Fixture input")
    int option032;
    @Option("option-033", '\0', "Fixture input")
    int option033;
    @Option("option-034", '\0', "Fixture input")
    int option034;
    @Option("option-035", '\0', "Fixture input")
    int option035;
    @Option("option-036", '\0', "Fixture input")
    int option036;
    @Option("option-037", '\0', "Fixture input")
    int option037;
    @Option("option-038", '\0', "Fixture input")
    int option038;
    @Option("option-039", '\0', "Fixture input")
    int option039;
    @Option("option-040", '\0', "Fixture input")
    int option040;
    @Option("option-041", '\0', "Fixture input")
    int option041;
    @Option("option-042", '\0', "Fixture input")
    int option042;
    @Option("option-043", '\0', "Fixture input")
    int option043;
    @Option("option-044", '\0', "Fixture input")
    int option044;
    @Option("option-045", '\0', "Fixture input")
    int option045;
    @Option("option-046", '\0', "Fixture input")
    int option046;
    @Option("option-047", '\0', "Fixture input")
    int option047;
    @Option("option-048", '\0', "Fixture input")
    int option048;
    @Option("option-049", '\0', "Fixture input")
    int option049;
    @Option("option-050", '\0', "Fixture input")
    int option050;
    @Option("option-051", '\0', "Fixture input")
    int option051;
    @Option("option-052", '\0', "Fixture input")
    int option052;
    @Option("option-053", '\0', "Fixture input")
    int option053;
    @Option("option-054", '\0', "Fixture input")
    int option054;
    @Option("option-055", '\0', "Fixture input")
    int option055;
    @Option("option-056", '\0', "Fixture input")
    int option056;
    @Option("option-057", '\0', "Fixture input")
    int option057;
    @Option("option-058", '\0', "Fixture input")
    int option058;
    @Option("option-059", '\0', "Fixture input")
    int option059;
    @Option("option-060", '\0', "Fixture input")
    int option060;
    @Option("option-061", '\0', "Fixture input")
    int option061;
    @Option("option-062", '\0', "Fixture input")
    int option062;
    @Option("option-063", '\0', "Fixture input")
    int option063;
}

private long checksum(scope ref const Fields64 fields) pure nothrow @nogc
{
    long sum;
    sum += fields.option000;
    sum += fields.option001;
    sum += fields.option002;
    sum += fields.option003;
    sum += fields.option004;
    sum += fields.option005;
    sum += fields.option006;
    sum += fields.option007;
    sum += fields.option008;
    sum += fields.option009;
    sum += fields.option010;
    sum += fields.option011;
    sum += fields.option012;
    sum += fields.option013;
    sum += fields.option014;
    sum += fields.option015;
    sum += fields.option016;
    sum += fields.option017;
    sum += fields.option018;
    sum += fields.option019;
    sum += fields.option020;
    sum += fields.option021;
    sum += fields.option022;
    sum += fields.option023;
    sum += fields.option024;
    sum += fields.option025;
    sum += fields.option026;
    sum += fields.option027;
    sum += fields.option028;
    sum += fields.option029;
    sum += fields.option030;
    sum += fields.option031;
    sum += fields.option032;
    sum += fields.option033;
    sum += fields.option034;
    sum += fields.option035;
    sum += fields.option036;
    sum += fields.option037;
    sum += fields.option038;
    sum += fields.option039;
    sum += fields.option040;
    sum += fields.option041;
    sum += fields.option042;
    sum += fields.option043;
    sum += fields.option044;
    sum += fields.option045;
    sum += fields.option046;
    sum += fields.option047;
    sum += fields.option048;
    sum += fields.option049;
    sum += fields.option050;
    sum += fields.option051;
    sum += fields.option052;
    sum += fields.option053;
    sum += fields.option054;
    sum += fields.option055;
    sum += fields.option056;
    sum += fields.option057;
    sum += fields.option058;
    sum += fields.option059;
    sum += fields.option060;
    sum += fields.option061;
    sum += fields.option062;
    sum += fields.option063;
    return sum;
}

version (FlintCliScale)
{
    @Command("fixture-256", "CLI metadata fixture")
    private struct Fields256
    {
        @Option("option-000", '\0', "Fixture input")
        int option000;
        @Option("option-001", '\0', "Fixture input")
        int option001;
        @Option("option-002", '\0', "Fixture input")
        int option002;
        @Option("option-003", '\0', "Fixture input")
        int option003;
        @Option("option-004", '\0', "Fixture input")
        int option004;
        @Option("option-005", '\0', "Fixture input")
        int option005;
        @Option("option-006", '\0', "Fixture input")
        int option006;
        @Option("option-007", '\0', "Fixture input")
        int option007;
        @Option("option-008", '\0', "Fixture input")
        int option008;
        @Option("option-009", '\0', "Fixture input")
        int option009;
        @Option("option-010", '\0', "Fixture input")
        int option010;
        @Option("option-011", '\0', "Fixture input")
        int option011;
        @Option("option-012", '\0', "Fixture input")
        int option012;
        @Option("option-013", '\0', "Fixture input")
        int option013;
        @Option("option-014", '\0', "Fixture input")
        int option014;
        @Option("option-015", '\0', "Fixture input")
        int option015;
        @Option("option-016", '\0', "Fixture input")
        int option016;
        @Option("option-017", '\0', "Fixture input")
        int option017;
        @Option("option-018", '\0', "Fixture input")
        int option018;
        @Option("option-019", '\0', "Fixture input")
        int option019;
        @Option("option-020", '\0', "Fixture input")
        int option020;
        @Option("option-021", '\0', "Fixture input")
        int option021;
        @Option("option-022", '\0', "Fixture input")
        int option022;
        @Option("option-023", '\0', "Fixture input")
        int option023;
        @Option("option-024", '\0', "Fixture input")
        int option024;
        @Option("option-025", '\0', "Fixture input")
        int option025;
        @Option("option-026", '\0', "Fixture input")
        int option026;
        @Option("option-027", '\0', "Fixture input")
        int option027;
        @Option("option-028", '\0', "Fixture input")
        int option028;
        @Option("option-029", '\0', "Fixture input")
        int option029;
        @Option("option-030", '\0', "Fixture input")
        int option030;
        @Option("option-031", '\0', "Fixture input")
        int option031;
        @Option("option-032", '\0', "Fixture input")
        int option032;
        @Option("option-033", '\0', "Fixture input")
        int option033;
        @Option("option-034", '\0', "Fixture input")
        int option034;
        @Option("option-035", '\0', "Fixture input")
        int option035;
        @Option("option-036", '\0', "Fixture input")
        int option036;
        @Option("option-037", '\0', "Fixture input")
        int option037;
        @Option("option-038", '\0', "Fixture input")
        int option038;
        @Option("option-039", '\0', "Fixture input")
        int option039;
        @Option("option-040", '\0', "Fixture input")
        int option040;
        @Option("option-041", '\0', "Fixture input")
        int option041;
        @Option("option-042", '\0', "Fixture input")
        int option042;
        @Option("option-043", '\0', "Fixture input")
        int option043;
        @Option("option-044", '\0', "Fixture input")
        int option044;
        @Option("option-045", '\0', "Fixture input")
        int option045;
        @Option("option-046", '\0', "Fixture input")
        int option046;
        @Option("option-047", '\0', "Fixture input")
        int option047;
        @Option("option-048", '\0', "Fixture input")
        int option048;
        @Option("option-049", '\0', "Fixture input")
        int option049;
        @Option("option-050", '\0', "Fixture input")
        int option050;
        @Option("option-051", '\0', "Fixture input")
        int option051;
        @Option("option-052", '\0', "Fixture input")
        int option052;
        @Option("option-053", '\0', "Fixture input")
        int option053;
        @Option("option-054", '\0', "Fixture input")
        int option054;
        @Option("option-055", '\0', "Fixture input")
        int option055;
        @Option("option-056", '\0', "Fixture input")
        int option056;
        @Option("option-057", '\0', "Fixture input")
        int option057;
        @Option("option-058", '\0', "Fixture input")
        int option058;
        @Option("option-059", '\0', "Fixture input")
        int option059;
        @Option("option-060", '\0', "Fixture input")
        int option060;
        @Option("option-061", '\0', "Fixture input")
        int option061;
        @Option("option-062", '\0', "Fixture input")
        int option062;
        @Option("option-063", '\0', "Fixture input")
        int option063;
        @Option("option-064", '\0', "Fixture input")
        int option064;
        @Option("option-065", '\0', "Fixture input")
        int option065;
        @Option("option-066", '\0', "Fixture input")
        int option066;
        @Option("option-067", '\0', "Fixture input")
        int option067;
        @Option("option-068", '\0', "Fixture input")
        int option068;
        @Option("option-069", '\0', "Fixture input")
        int option069;
        @Option("option-070", '\0', "Fixture input")
        int option070;
        @Option("option-071", '\0', "Fixture input")
        int option071;
        @Option("option-072", '\0', "Fixture input")
        int option072;
        @Option("option-073", '\0', "Fixture input")
        int option073;
        @Option("option-074", '\0', "Fixture input")
        int option074;
        @Option("option-075", '\0', "Fixture input")
        int option075;
        @Option("option-076", '\0', "Fixture input")
        int option076;
        @Option("option-077", '\0', "Fixture input")
        int option077;
        @Option("option-078", '\0', "Fixture input")
        int option078;
        @Option("option-079", '\0', "Fixture input")
        int option079;
        @Option("option-080", '\0', "Fixture input")
        int option080;
        @Option("option-081", '\0', "Fixture input")
        int option081;
        @Option("option-082", '\0', "Fixture input")
        int option082;
        @Option("option-083", '\0', "Fixture input")
        int option083;
        @Option("option-084", '\0', "Fixture input")
        int option084;
        @Option("option-085", '\0', "Fixture input")
        int option085;
        @Option("option-086", '\0', "Fixture input")
        int option086;
        @Option("option-087", '\0', "Fixture input")
        int option087;
        @Option("option-088", '\0', "Fixture input")
        int option088;
        @Option("option-089", '\0', "Fixture input")
        int option089;
        @Option("option-090", '\0', "Fixture input")
        int option090;
        @Option("option-091", '\0', "Fixture input")
        int option091;
        @Option("option-092", '\0', "Fixture input")
        int option092;
        @Option("option-093", '\0', "Fixture input")
        int option093;
        @Option("option-094", '\0', "Fixture input")
        int option094;
        @Option("option-095", '\0', "Fixture input")
        int option095;
        @Option("option-096", '\0', "Fixture input")
        int option096;
        @Option("option-097", '\0', "Fixture input")
        int option097;
        @Option("option-098", '\0', "Fixture input")
        int option098;
        @Option("option-099", '\0', "Fixture input")
        int option099;
        @Option("option-100", '\0', "Fixture input")
        int option100;
        @Option("option-101", '\0', "Fixture input")
        int option101;
        @Option("option-102", '\0', "Fixture input")
        int option102;
        @Option("option-103", '\0', "Fixture input")
        int option103;
        @Option("option-104", '\0', "Fixture input")
        int option104;
        @Option("option-105", '\0', "Fixture input")
        int option105;
        @Option("option-106", '\0', "Fixture input")
        int option106;
        @Option("option-107", '\0', "Fixture input")
        int option107;
        @Option("option-108", '\0', "Fixture input")
        int option108;
        @Option("option-109", '\0', "Fixture input")
        int option109;
        @Option("option-110", '\0', "Fixture input")
        int option110;
        @Option("option-111", '\0', "Fixture input")
        int option111;
        @Option("option-112", '\0', "Fixture input")
        int option112;
        @Option("option-113", '\0', "Fixture input")
        int option113;
        @Option("option-114", '\0', "Fixture input")
        int option114;
        @Option("option-115", '\0', "Fixture input")
        int option115;
        @Option("option-116", '\0', "Fixture input")
        int option116;
        @Option("option-117", '\0', "Fixture input")
        int option117;
        @Option("option-118", '\0', "Fixture input")
        int option118;
        @Option("option-119", '\0', "Fixture input")
        int option119;
        @Option("option-120", '\0', "Fixture input")
        int option120;
        @Option("option-121", '\0', "Fixture input")
        int option121;
        @Option("option-122", '\0', "Fixture input")
        int option122;
        @Option("option-123", '\0', "Fixture input")
        int option123;
        @Option("option-124", '\0', "Fixture input")
        int option124;
        @Option("option-125", '\0', "Fixture input")
        int option125;
        @Option("option-126", '\0', "Fixture input")
        int option126;
        @Option("option-127", '\0', "Fixture input")
        int option127;
        @Option("option-128", '\0', "Fixture input")
        int option128;
        @Option("option-129", '\0', "Fixture input")
        int option129;
        @Option("option-130", '\0', "Fixture input")
        int option130;
        @Option("option-131", '\0', "Fixture input")
        int option131;
        @Option("option-132", '\0', "Fixture input")
        int option132;
        @Option("option-133", '\0', "Fixture input")
        int option133;
        @Option("option-134", '\0', "Fixture input")
        int option134;
        @Option("option-135", '\0', "Fixture input")
        int option135;
        @Option("option-136", '\0', "Fixture input")
        int option136;
        @Option("option-137", '\0', "Fixture input")
        int option137;
        @Option("option-138", '\0', "Fixture input")
        int option138;
        @Option("option-139", '\0', "Fixture input")
        int option139;
        @Option("option-140", '\0', "Fixture input")
        int option140;
        @Option("option-141", '\0', "Fixture input")
        int option141;
        @Option("option-142", '\0', "Fixture input")
        int option142;
        @Option("option-143", '\0', "Fixture input")
        int option143;
        @Option("option-144", '\0', "Fixture input")
        int option144;
        @Option("option-145", '\0', "Fixture input")
        int option145;
        @Option("option-146", '\0', "Fixture input")
        int option146;
        @Option("option-147", '\0', "Fixture input")
        int option147;
        @Option("option-148", '\0', "Fixture input")
        int option148;
        @Option("option-149", '\0', "Fixture input")
        int option149;
        @Option("option-150", '\0', "Fixture input")
        int option150;
        @Option("option-151", '\0', "Fixture input")
        int option151;
        @Option("option-152", '\0', "Fixture input")
        int option152;
        @Option("option-153", '\0', "Fixture input")
        int option153;
        @Option("option-154", '\0', "Fixture input")
        int option154;
        @Option("option-155", '\0', "Fixture input")
        int option155;
        @Option("option-156", '\0', "Fixture input")
        int option156;
        @Option("option-157", '\0', "Fixture input")
        int option157;
        @Option("option-158", '\0', "Fixture input")
        int option158;
        @Option("option-159", '\0', "Fixture input")
        int option159;
        @Option("option-160", '\0', "Fixture input")
        int option160;
        @Option("option-161", '\0', "Fixture input")
        int option161;
        @Option("option-162", '\0', "Fixture input")
        int option162;
        @Option("option-163", '\0', "Fixture input")
        int option163;
        @Option("option-164", '\0', "Fixture input")
        int option164;
        @Option("option-165", '\0', "Fixture input")
        int option165;
        @Option("option-166", '\0', "Fixture input")
        int option166;
        @Option("option-167", '\0', "Fixture input")
        int option167;
        @Option("option-168", '\0', "Fixture input")
        int option168;
        @Option("option-169", '\0', "Fixture input")
        int option169;
        @Option("option-170", '\0', "Fixture input")
        int option170;
        @Option("option-171", '\0', "Fixture input")
        int option171;
        @Option("option-172", '\0', "Fixture input")
        int option172;
        @Option("option-173", '\0', "Fixture input")
        int option173;
        @Option("option-174", '\0', "Fixture input")
        int option174;
        @Option("option-175", '\0', "Fixture input")
        int option175;
        @Option("option-176", '\0', "Fixture input")
        int option176;
        @Option("option-177", '\0', "Fixture input")
        int option177;
        @Option("option-178", '\0', "Fixture input")
        int option178;
        @Option("option-179", '\0', "Fixture input")
        int option179;
        @Option("option-180", '\0', "Fixture input")
        int option180;
        @Option("option-181", '\0', "Fixture input")
        int option181;
        @Option("option-182", '\0', "Fixture input")
        int option182;
        @Option("option-183", '\0', "Fixture input")
        int option183;
        @Option("option-184", '\0', "Fixture input")
        int option184;
        @Option("option-185", '\0', "Fixture input")
        int option185;
        @Option("option-186", '\0', "Fixture input")
        int option186;
        @Option("option-187", '\0', "Fixture input")
        int option187;
        @Option("option-188", '\0', "Fixture input")
        int option188;
        @Option("option-189", '\0', "Fixture input")
        int option189;
        @Option("option-190", '\0', "Fixture input")
        int option190;
        @Option("option-191", '\0', "Fixture input")
        int option191;
        @Option("option-192", '\0', "Fixture input")
        int option192;
        @Option("option-193", '\0', "Fixture input")
        int option193;
        @Option("option-194", '\0', "Fixture input")
        int option194;
        @Option("option-195", '\0', "Fixture input")
        int option195;
        @Option("option-196", '\0', "Fixture input")
        int option196;
        @Option("option-197", '\0', "Fixture input")
        int option197;
        @Option("option-198", '\0', "Fixture input")
        int option198;
        @Option("option-199", '\0', "Fixture input")
        int option199;
        @Option("option-200", '\0', "Fixture input")
        int option200;
        @Option("option-201", '\0', "Fixture input")
        int option201;
        @Option("option-202", '\0', "Fixture input")
        int option202;
        @Option("option-203", '\0', "Fixture input")
        int option203;
        @Option("option-204", '\0', "Fixture input")
        int option204;
        @Option("option-205", '\0', "Fixture input")
        int option205;
        @Option("option-206", '\0', "Fixture input")
        int option206;
        @Option("option-207", '\0', "Fixture input")
        int option207;
        @Option("option-208", '\0', "Fixture input")
        int option208;
        @Option("option-209", '\0', "Fixture input")
        int option209;
        @Option("option-210", '\0', "Fixture input")
        int option210;
        @Option("option-211", '\0', "Fixture input")
        int option211;
        @Option("option-212", '\0', "Fixture input")
        int option212;
        @Option("option-213", '\0', "Fixture input")
        int option213;
        @Option("option-214", '\0', "Fixture input")
        int option214;
        @Option("option-215", '\0', "Fixture input")
        int option215;
        @Option("option-216", '\0', "Fixture input")
        int option216;
        @Option("option-217", '\0', "Fixture input")
        int option217;
        @Option("option-218", '\0', "Fixture input")
        int option218;
        @Option("option-219", '\0', "Fixture input")
        int option219;
        @Option("option-220", '\0', "Fixture input")
        int option220;
        @Option("option-221", '\0', "Fixture input")
        int option221;
        @Option("option-222", '\0', "Fixture input")
        int option222;
        @Option("option-223", '\0', "Fixture input")
        int option223;
        @Option("option-224", '\0', "Fixture input")
        int option224;
        @Option("option-225", '\0', "Fixture input")
        int option225;
        @Option("option-226", '\0', "Fixture input")
        int option226;
        @Option("option-227", '\0', "Fixture input")
        int option227;
        @Option("option-228", '\0', "Fixture input")
        int option228;
        @Option("option-229", '\0', "Fixture input")
        int option229;
        @Option("option-230", '\0', "Fixture input")
        int option230;
        @Option("option-231", '\0', "Fixture input")
        int option231;
        @Option("option-232", '\0', "Fixture input")
        int option232;
        @Option("option-233", '\0', "Fixture input")
        int option233;
        @Option("option-234", '\0', "Fixture input")
        int option234;
        @Option("option-235", '\0', "Fixture input")
        int option235;
        @Option("option-236", '\0', "Fixture input")
        int option236;
        @Option("option-237", '\0', "Fixture input")
        int option237;
        @Option("option-238", '\0', "Fixture input")
        int option238;
        @Option("option-239", '\0', "Fixture input")
        int option239;
        @Option("option-240", '\0', "Fixture input")
        int option240;
        @Option("option-241", '\0', "Fixture input")
        int option241;
        @Option("option-242", '\0', "Fixture input")
        int option242;
        @Option("option-243", '\0', "Fixture input")
        int option243;
        @Option("option-244", '\0', "Fixture input")
        int option244;
        @Option("option-245", '\0', "Fixture input")
        int option245;
        @Option("option-246", '\0', "Fixture input")
        int option246;
        @Option("option-247", '\0', "Fixture input")
        int option247;
        @Option("option-248", '\0', "Fixture input")
        int option248;
        @Option("option-249", '\0', "Fixture input")
        int option249;
        @Option("option-250", '\0', "Fixture input")
        int option250;
        @Option("option-251", '\0', "Fixture input")
        int option251;
        @Option("option-252", '\0', "Fixture input")
        int option252;
        @Option("option-253", '\0', "Fixture input")
        int option253;
        @Option("option-254", '\0', "Fixture input")
        int option254;
        @Option("option-255", '\0', "Fixture input")
        int option255;
    }

    private long checksum(scope ref const Fields256 fields) pure nothrow @nogc
    {
        long sum;
        sum += fields.option000;
        sum += fields.option001;
        sum += fields.option002;
        sum += fields.option003;
        sum += fields.option004;
        sum += fields.option005;
        sum += fields.option006;
        sum += fields.option007;
        sum += fields.option008;
        sum += fields.option009;
        sum += fields.option010;
        sum += fields.option011;
        sum += fields.option012;
        sum += fields.option013;
        sum += fields.option014;
        sum += fields.option015;
        sum += fields.option016;
        sum += fields.option017;
        sum += fields.option018;
        sum += fields.option019;
        sum += fields.option020;
        sum += fields.option021;
        sum += fields.option022;
        sum += fields.option023;
        sum += fields.option024;
        sum += fields.option025;
        sum += fields.option026;
        sum += fields.option027;
        sum += fields.option028;
        sum += fields.option029;
        sum += fields.option030;
        sum += fields.option031;
        sum += fields.option032;
        sum += fields.option033;
        sum += fields.option034;
        sum += fields.option035;
        sum += fields.option036;
        sum += fields.option037;
        sum += fields.option038;
        sum += fields.option039;
        sum += fields.option040;
        sum += fields.option041;
        sum += fields.option042;
        sum += fields.option043;
        sum += fields.option044;
        sum += fields.option045;
        sum += fields.option046;
        sum += fields.option047;
        sum += fields.option048;
        sum += fields.option049;
        sum += fields.option050;
        sum += fields.option051;
        sum += fields.option052;
        sum += fields.option053;
        sum += fields.option054;
        sum += fields.option055;
        sum += fields.option056;
        sum += fields.option057;
        sum += fields.option058;
        sum += fields.option059;
        sum += fields.option060;
        sum += fields.option061;
        sum += fields.option062;
        sum += fields.option063;
        sum += fields.option064;
        sum += fields.option065;
        sum += fields.option066;
        sum += fields.option067;
        sum += fields.option068;
        sum += fields.option069;
        sum += fields.option070;
        sum += fields.option071;
        sum += fields.option072;
        sum += fields.option073;
        sum += fields.option074;
        sum += fields.option075;
        sum += fields.option076;
        sum += fields.option077;
        sum += fields.option078;
        sum += fields.option079;
        sum += fields.option080;
        sum += fields.option081;
        sum += fields.option082;
        sum += fields.option083;
        sum += fields.option084;
        sum += fields.option085;
        sum += fields.option086;
        sum += fields.option087;
        sum += fields.option088;
        sum += fields.option089;
        sum += fields.option090;
        sum += fields.option091;
        sum += fields.option092;
        sum += fields.option093;
        sum += fields.option094;
        sum += fields.option095;
        sum += fields.option096;
        sum += fields.option097;
        sum += fields.option098;
        sum += fields.option099;
        sum += fields.option100;
        sum += fields.option101;
        sum += fields.option102;
        sum += fields.option103;
        sum += fields.option104;
        sum += fields.option105;
        sum += fields.option106;
        sum += fields.option107;
        sum += fields.option108;
        sum += fields.option109;
        sum += fields.option110;
        sum += fields.option111;
        sum += fields.option112;
        sum += fields.option113;
        sum += fields.option114;
        sum += fields.option115;
        sum += fields.option116;
        sum += fields.option117;
        sum += fields.option118;
        sum += fields.option119;
        sum += fields.option120;
        sum += fields.option121;
        sum += fields.option122;
        sum += fields.option123;
        sum += fields.option124;
        sum += fields.option125;
        sum += fields.option126;
        sum += fields.option127;
        sum += fields.option128;
        sum += fields.option129;
        sum += fields.option130;
        sum += fields.option131;
        sum += fields.option132;
        sum += fields.option133;
        sum += fields.option134;
        sum += fields.option135;
        sum += fields.option136;
        sum += fields.option137;
        sum += fields.option138;
        sum += fields.option139;
        sum += fields.option140;
        sum += fields.option141;
        sum += fields.option142;
        sum += fields.option143;
        sum += fields.option144;
        sum += fields.option145;
        sum += fields.option146;
        sum += fields.option147;
        sum += fields.option148;
        sum += fields.option149;
        sum += fields.option150;
        sum += fields.option151;
        sum += fields.option152;
        sum += fields.option153;
        sum += fields.option154;
        sum += fields.option155;
        sum += fields.option156;
        sum += fields.option157;
        sum += fields.option158;
        sum += fields.option159;
        sum += fields.option160;
        sum += fields.option161;
        sum += fields.option162;
        sum += fields.option163;
        sum += fields.option164;
        sum += fields.option165;
        sum += fields.option166;
        sum += fields.option167;
        sum += fields.option168;
        sum += fields.option169;
        sum += fields.option170;
        sum += fields.option171;
        sum += fields.option172;
        sum += fields.option173;
        sum += fields.option174;
        sum += fields.option175;
        sum += fields.option176;
        sum += fields.option177;
        sum += fields.option178;
        sum += fields.option179;
        sum += fields.option180;
        sum += fields.option181;
        sum += fields.option182;
        sum += fields.option183;
        sum += fields.option184;
        sum += fields.option185;
        sum += fields.option186;
        sum += fields.option187;
        sum += fields.option188;
        sum += fields.option189;
        sum += fields.option190;
        sum += fields.option191;
        sum += fields.option192;
        sum += fields.option193;
        sum += fields.option194;
        sum += fields.option195;
        sum += fields.option196;
        sum += fields.option197;
        sum += fields.option198;
        sum += fields.option199;
        sum += fields.option200;
        sum += fields.option201;
        sum += fields.option202;
        sum += fields.option203;
        sum += fields.option204;
        sum += fields.option205;
        sum += fields.option206;
        sum += fields.option207;
        sum += fields.option208;
        sum += fields.option209;
        sum += fields.option210;
        sum += fields.option211;
        sum += fields.option212;
        sum += fields.option213;
        sum += fields.option214;
        sum += fields.option215;
        sum += fields.option216;
        sum += fields.option217;
        sum += fields.option218;
        sum += fields.option219;
        sum += fields.option220;
        sum += fields.option221;
        sum += fields.option222;
        sum += fields.option223;
        sum += fields.option224;
        sum += fields.option225;
        sum += fields.option226;
        sum += fields.option227;
        sum += fields.option228;
        sum += fields.option229;
        sum += fields.option230;
        sum += fields.option231;
        sum += fields.option232;
        sum += fields.option233;
        sum += fields.option234;
        sum += fields.option235;
        sum += fields.option236;
        sum += fields.option237;
        sum += fields.option238;
        sum += fields.option239;
        sum += fields.option240;
        sum += fields.option241;
        sum += fields.option242;
        sum += fields.option243;
        sum += fields.option244;
        sum += fields.option245;
        sum += fields.option246;
        sum += fields.option247;
        sum += fields.option248;
        sum += fields.option249;
        sum += fields.option250;
        sum += fields.option251;
        sum += fields.option252;
        sum += fields.option253;
        sum += fields.option254;
        sum += fields.option255;
        return sum;
    }
}

pragma(inline, false) private long trial(T, size_t width)(scope const(char)[] argument, size_t declared)
{
    check(declared == width);
    const response = parse!T([argument]);
    check(response.error.code == Status.ok);
    return checksum(response.options);
}

void main(string[] args)
{
    check(args.length == 1 || (args.length == 2 && args[1] == "--measure"));
    const measure = args.length == 2;
    version (FlintCliScale)
    {
        printChecksum(10, runProbe(&trial!(Fields10, 10), 10, measure));
        printChecksum(256, runProbe(&trial!(Fields256, 256), 256, measure));
    }
    printChecksum(64, runProbe(&trial!(Fields64, 64), 64, measure));
}
