// Writes the golden file that framework/java/tests/time_test.d compares: DateTimeFormatter.RFC_1123_DATE_TIME
// formatting, and its lenient SMART parsing into each temporal type, with the result's toString() or `!` and the
// exception message (and a parse exception's error index). Each line is `kind<TAB>input<TAB>result`.
//   javac GoldenRfc1123.java && java GoldenRfc1123 rfc1123.tsv
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.*;
import java.time.format.*;
import java.util.ArrayList;
import java.util.List;

public class GoldenRfc1123 {
    static final List<String> lines = new ArrayList<>();

    static final DateTimeFormatter F = DateTimeFormatter.RFC_1123_DATE_TIME;

    static String err(Throwable e) {
        String s = "!" + e.getMessage();
        if (e instanceof DateTimeParseException p) s += "\t" + p.getErrorIndex();
        return s;
    }

    static void row(String op, String in, java.util.function.Supplier<Object> f) {
        String out;
        try { out = String.valueOf(f.get()); } catch (DateTimeException e) { out = err(e); }
        lines.add(op + "\t" + in + "\t" + out);
    }

    public static void main(String[] a) throws Exception {
        lines.add("toString\t-\t" + F);
        // format
        int[][] odts = {
            {2008, 6, 3, 11, 5, 30, 0, 0}, {2008, 6, 13, 11, 5, 30, 0, 0}, {2024, 2, 29, 0, 0, 0, 0, 5400},
            {1999, 12, 31, 23, 59, 59, 999999999, -18000}, {999, 1, 1, 1, 2, 3, 0, 0}, {1, 1, 1, 0, 0, 0, 0, 0},
            {9999, 12, 31, 23, 59, 59, 0, 64800}, {10000, 1, 1, 0, 0, 0, 0, 0}, {0, 1, 1, 0, 0, 0, 0, 0},
            {-1, 1, 1, 0, 0, 0, 0, 0}, {2008, 6, 3, 11, 5, 30, 0, 5445}, {2008, 6, 3, 11, 5, 30, 0, -5445},
            {2008, 6, 3, 11, 5, 0, 0, -64800}, {2008, 6, 3, 11, 5, 30, 0, 45},
        };
        for (int[] v : odts) {
            OffsetDateTime o = OffsetDateTime.of(v[0], v[1], v[2], v[3], v[4], v[5], v[6], ZoneOffset.ofTotalSeconds(v[7]));
            row("formatOffsetDateTime", o.toString(), () -> F.format(o));
        }
        for (int m = 1; m <= 12; m++) {
            OffsetDateTime o = OffsetDateTime.of(2023, m, m + 1, 8, 49, 37, 0, ZoneOffset.UTC);
            row("formatOffsetDateTime", o.toString(), () -> F.format(o));
        }
        ZonedDateTime z = ZonedDateTime.of(2008, 6, 3, 11, 5, 30, 0, ZoneOffset.ofHours(2));
        row("formatZonedDateTime", z.toString(), () -> F.format(z));
        ZonedDateTime zu = ZonedDateTime.of(2008, 6, 3, 11, 5, 30, 0, ZoneId.of("UTC"));
        row("formatZonedDateTime", zu.toString(), () -> F.format(zu));
        LocalDateTime ldt = LocalDateTime.of(2008, 6, 3, 11, 5, 30);
        row("formatLocalDateTime", ldt.toString(), () -> F.format(ldt));
        LocalDate ld = LocalDate.of(2008, 6, 3);
        row("formatLocalDate", ld.toString(), () -> F.format(ld));
        LocalTime lt = LocalTime.of(11, 5, 30);
        row("formatLocalTime", lt.toString(), () -> F.format(lt));
        Instant in = Instant.ofEpochSecond(1212491130);
        row("formatInstant", in.toString(), () -> F.format(in));
        row("formatInstantWithZone", in.toString(), () -> F.withZone(ZoneOffset.UTC).format(in));

        String[] texts = {
            "Tue, 3 Jun 2008 11:05:30 GMT", "Tue, 03 Jun 2008 11:05:30 GMT", "3 Jun 2008 11:05:30 GMT",
            "Tue, 3 Jun 2008 11:05 GMT", "Tue, 3 Jun 2008 11:05:30 +0200", "Tue, 3 Jun 2008 11:05:30 -0530",
            "Tue, 3 Jun 2008 11:05:30 +02:00", "Tue, 3 Jun 2008 11:05:30 +02", "Tue, 3 Jun 2008 11:05:30 +020030",
            "Tue, 3 Jun 2008 11:05:30 +02:00:30", "Tue, 3 Jun 2008 11:05:30 +2", "Tue, 3 Jun 2008 11:05:30 +0260",
            "Tue, 3 Jun 2008 11:05:30 +2400", "Tue, 3 Jun 2008 11:05:30 +0000", "Tue, 3 Jun 2008 11:05:30 -0000",
            "Tue, 3 Jun 2008 11:05:30 Z", "Tue, 3 Jun 2008 11:05:30 UT", "Tue, 3 Jun 2008 11:05:30 UTC",
            "Tue, 3 Jun 2008 11:05:30 EST", "Tue, 3 Jun 2008 11:05:30 gmt", "TUE, 3 JUN 2008 11:05:30 GMT",
            "tue, 3 jun 2008 11:05:30 gmt", "Wed, 3 Jun 2008 11:05:30 GMT", "Tuesday, 3 Jun 2008 11:05:30 GMT",
            "Tue, 3 June 2008 11:05:30 GMT", "Tue, 3 6 2008 11:05:30 GMT", "2, 3 Jun 2008 11:05:30 GMT",
            "3, 3 Jun 2008 11:05:30 GMT", "Tue, 3 +6 2008 11:05:30 GMT", "Tue, 3 13 2008 11:05:30 GMT",
            "Tue, 3 Jun 08 11:05:30 GMT", "Tue, 3 Jun 12008 11:05:30 GMT", "Tue, 3 Jun 123456789 11:05:30 GMT",
            "Tue, 3 Jun 1234567890 11:05:30 GMT", "Tue, 3 Jun 2008 1:5:3 GMT", "Tue, 3 Jun 2008 011:005:030 GMT",
            "Tue, 003 Jun 2008 11:05:30 GMT", "Tue, +3 Jun 2008 11:05:30 GMT", "Tue, -3 Jun 2008 11:05:30 GMT",
            "Tue, 3 Jun +2008 11:05:30 GMT", "Tue, 3 Jun -2008 11:05:30 GMT", "Tue, 3 Jun 2008 +11:05:30 GMT",
            "Tue, 31 Jun 2008 11:05:30 GMT", "Tue, 32 Jun 2008 11:05:30 GMT", "Tue, 0 Jun 2008 11:05:30 GMT",
            "Tue, 3 Jun 2008 24:05:30 GMT", "Tue, 3 Jun 2008 11:60:30 GMT", "Tue, 3 Jun 2008 11:05:60 GMT",
            "Tue, 3 Jun 2008 11:05:30", "Tue, 3 Jun 2008 11:05:30 GMT ", "Tue,3 Jun 2008 11:05:30 GMT",
            "Tue, 3  Jun 2008 11:05:30 GMT", "Tue, 3 Jun 2008 11:05:30.5 GMT", "Tue 3 Jun 2008 11:05:30 GMT",
            "", "Tue, ", "Fri, 29 Feb 2008 11:05:30 GMT", "Sun, 29 Feb 2009 11:05:30 GMT",
            "Mon, 29 Feb 2010 11:05:30 GMT", "Sat, 1 Jan 0 00:00:00 GMT", "Mon, 1 Jan 1 00:00:00 GMT",
            "Fri, 31 Dec 9999 23:59:59 GMT", "Sat, 1 Jan 10000 00:00:00 GMT", "Tue, 3 Jun 2008 11:05:30 +1800",
            "Tue, 3 Jun 2008 11:05:30 +1801", "Tue, 3 Jun 2008 11:05:30 +0130 GMT", "Tue, 3 Jun 2008 11:5 GMT",
            "Tue, 3 Jun 2008 11: GMT", "Tue, 3 Jun 2008 11:05: GMT", "Tue, 3 Jun 2008 11:05:30 +01:3",
            "Tue, 3 Jun 2008 11:05:30 +013", "Tue, 3 Jun 2008 11:05:30 +01300", "Tue, 3 Jun 2008 11:05:30 +0130:00",
            "Tue, 3 Jun 2008 11:05:30 +a", "Tue, 3 jUN 2008 11:05:30 GmT", "0, 3 Jun 2008 11:05:30 GMT",
            "8, 3 Jun 2008 11:05:30 GMT", "Tue, 3 0 2008 11:05:30 GMT", "Tue, 3 Jun 2008 11:05:30 é",
            "éue, 3 Jun 2008 11:05:30 GMT", "Tue, 3 Jun 2é08 11:05:30 GMT",
            "Tue, 3 Jun 2008 24:00:00 GMT", "Tue, 3 Jun 2008 24:00 GMT", "Tue, 3 Jun 2008 24:00:01 GMT", "Wed, 31 Dec 2008 24:00 GMT", "Wed, 4 Jun 2008 24:00 GMT", "Thu, 31 Feb 2024 10:00 GMT", "Tue, 31 Feb 2023 10:00 GMT", "Wed, 30 Feb 2024 10:00 GMT", "Thu, 31 Apr 2008 10:00 GMT", "Wed, 30 Apr 2008 10:00 GMT", "Tue, 3 Jun 2008 11:05:30 +9999", "Tue, 3 Jun 2008 11:05:30 +0099", "Tue, 3 Jun 2008 11:05:30 +010099", "Tue, 3 Jun 2008 11:05:30 +013060", "Tue, 3 Jun 2008 11:05:30 +0130599", "Tue, 3 06 2008 11:05:30 GMT", "Tue, 3 0006 2008 11:05:30 GMT", "Tue, 3 1234567890 2008 11:05:30 GMT", "Tue, 1234567890 Jun 2008 11:05:30 GMT", "Tue, 123456789 Jun 2008 11:05:30 GMT", "+2, 3 Jun 2008 11:05:30 GMT", "-2, 3 Jun 2008 11:05:30 GMT", "02, 3 Jun 2008 11:05:30 GMT", "Tue, 3 -6 2008 11:05:30 GMT", "Tue, 3 Jun  2008 11:05:30 GMT", "Tue, 3 Jun 2008 123456789:05 GMT", "Tue, 3 Jun 2008 1234567890:05 GMT", "Tue, 3 Jun 2008 11:05:30 +-0100", "Tue, 3 Jun 2008 11:05:30 -1800", "Tue, 3 Jun 2008 11:05:30 -1801", "Tue, 3 Jun 2008 11:05:30 -2400", "Tue, 3 Jun 2008 11:05:30 GMT+01", "Tue, 3 Jun 2008 11:05:30 +0", "Mon, 31 Dec -1 00:00 GMT", "Tue, 3 Jun 2008 00:00:00.000 GMT", "Tue, 3 Jun 2008 11:5:30 GmT", "Tue, 9 Jun 2008 11:05:30 GMT", "Mon, 9 Jun 2008 11:05:30 GMT",
        };
        for (String t : texts) {
            row("parseOffsetDateTime", t, () -> OffsetDateTime.parse(t, F));
            row("parseZonedDateTime", t, () -> ZonedDateTime.parse(t, F));
            row("parseLocalDateTime", t, () -> LocalDateTime.parse(t, F));
            row("parseLocalDate", t, () -> LocalDate.parse(t, F));
            row("parseLocalTime", t, () -> LocalTime.parse(t, F));
        }
        Files.write(Path.of(a[0]), lines);
    }
}
