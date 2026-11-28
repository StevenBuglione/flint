// Generate tests/base64-java21.tsv with Java SE 21.
//
// Rows, tab-separated:
//   E <encoder> <input hex> <encoded text>
//   D <decoder> <input hex> <output hex> | !<IllegalArgumentException message>
//   S <decoder> <input as UTF-8 hex> <output hex> | !<message>   (decode(String))
//   M <line length> <separator hex> <input hex> <encoded hex> | !<message>   (getMimeEncoder(int, byte[]))
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

class Base64Oracle {
    static final HexFormat HEX = HexFormat.of();
    static final List<String> DECODED = List.of("basic", "url-np", "mime", "mime10lf-np");

    static String hex(byte[] bytes) {
        return bytes.length == 0 ? "-" : HEX.formatHex(bytes);
    }

    static String decodeRow(Base64.Decoder decoder, byte[] src) {
        try {
            return hex(decoder.decode(src));
        } catch (IllegalArgumentException e) {
            return "!" + e.getMessage();
        }
    }

    static String decodeStringRow(Base64.Decoder decoder, String src) {
        try {
            return hex(decoder.decode(src));
        } catch (IllegalArgumentException e) {
            return "!" + e.getMessage();
        }
    }

    public static void main(String[] args) {
        if (Runtime.version().feature() != 21)
            throw new IllegalStateException("Generate the corpus with Java SE 21");

        Map<String, Base64.Encoder> encoders = new LinkedHashMap<>();
        encoders.put("basic", Base64.getEncoder());
        encoders.put("url", Base64.getUrlEncoder());
        encoders.put("mime", Base64.getMimeEncoder());
        encoders.put("basic-np", Base64.getEncoder().withoutPadding());
        encoders.put("url-np", Base64.getUrlEncoder().withoutPadding());
        encoders.put("mime-np", Base64.getMimeEncoder().withoutPadding());
        encoders.put("mime10lf", Base64.getMimeEncoder(10, new byte[] {'\n'}));
        encoders.put("mime10lf-np", Base64.getMimeEncoder(10, new byte[] {'\n'}).withoutPadding());
        encoders.put("mime8none", Base64.getMimeEncoder(8, new byte[0]));
        Map<String, Base64.Decoder> decoders = new LinkedHashMap<>();
        decoders.put("basic", Base64.getDecoder());
        decoders.put("url", Base64.getUrlDecoder());
        decoders.put("mime", Base64.getMimeDecoder());

        Random random = new Random(21);
        List<byte[]> inputs = new ArrayList<>();
        for (int length = 0; length <= 40; ++length) {
            byte[] bytes = new byte[length];
            random.nextBytes(bytes);
            inputs.add(bytes);
        }
        for (int length : new int[] {57, 58, 59, 113, 230}) {
            byte[] bytes = new byte[length];
            random.nextBytes(bytes);
            inputs.add(bytes);
        }
        inputs.add(new byte[] {(byte) 0xfb, (byte) 0xff, (byte) 0xfe});
        inputs.add(new byte[] {(byte) 0xff, (byte) 0xff, (byte) 0xff, (byte) 0xff});

        List<byte[]> encoded = new ArrayList<>();
        for (Map.Entry<String, Base64.Encoder> entry : encoders.entrySet()) {
            for (byte[] input : inputs) {
                String text = entry.getValue().encodeToString(input);
                System.out.printf("E\t%s\t%s\t%s%n", entry.getKey(), hex(input), hex(text.getBytes(StandardCharsets.ISO_8859_1)));
                if (DECODED.contains(entry.getKey()))
                    encoded.add(text.getBytes(StandardCharsets.ISO_8859_1));
            }
        }

        String[] malformed = {
            "", "Q", "QQ", "QQ=", "QQ==", "QQ===", "QUI", "QUI=", "QUI==", "QUJD", "QUJD=", "=", "==", "====",
            "Q=", "Q===", "QQ=Q", "QQ==QUJD", "QUJDQ", "QUJDQQ", "QUJDQUI", "QUJD\r\nQUJD", "QUJD QUJD",
            "QU\nJD", "QUJD\n", "\nQUJD", "QUJD!", "!QUJD", "QUJ$", "QUJD====", "QUJDQUJD=QUJD", "-_-_", "+/+/",
            "Pz8/", "Pz8_", "Pz8-", "QUJD\u0080", "QUJDQUJDQUJDQUJD\r\n", "QUJDQUJDQUJD\r\nQUJD", "QQ==\r\n",
            "QQ==\r\nQUJD", "QQ\r\n==", "Q\r\nQ==", "QUJD=\r\n", "#", "##", "QU#JD", "QUJD#Q=", "QUJDQQ=#",
        };
        for (Map.Entry<String, Base64.Decoder> entry : decoders.entrySet()) {
            for (byte[] src : encoded)
                System.out.printf("D\t%s\t%s\t%s%n", entry.getKey(), hex(src), decodeRow(entry.getValue(), src));
            for (String text : malformed) {
                byte[] src = text.getBytes(StandardCharsets.ISO_8859_1);
                System.out.printf("D\t%s\t%s\t%s%n", entry.getKey(), hex(src), decodeRow(entry.getValue(), src));
            }
            for (byte b = Byte.MIN_VALUE; ; ++b) {
                byte[] src = {'Q', 'U', 'J', 'D', b, 'Q', '=', '='};
                System.out.printf("D\t%s\t%s\t%s%n", entry.getKey(), hex(src), decodeRow(entry.getValue(), src));
                if (b == Byte.MAX_VALUE)
                    break;
            }
        }

        String[] texts = {
            "", "QUJD", "QUJDé", "QUJDéQQ==", "QUJD€", "QUJD😀QQ==", "Pz8/", "ÿÿ",
            "QUJD\r\néQUJD", "QUJDĀQQ==",
        };
        for (Map.Entry<String, Base64.Decoder> entry : decoders.entrySet()) {
            for (String text : texts) {
                System.out.printf("S\t%s\t%s\t%s%n", entry.getKey(), hex(text.getBytes(StandardCharsets.UTF_8)),
                    decodeStringRow(entry.getValue(), text));
            }
        }

        byte[] sample = new byte[16];
        new Random(4648).nextBytes(sample);
        int[] lengths = {-8, 0, 3, 4, 5, 7, 8, 11, 12, 76, 77};
        byte[][] separators = {{}, {'\r', '\n'}, {'\n'}, {'.', '.'}, {'A'}, {'='}, {'\n', '+'}, {'-'}, {'_'},
                               {(byte) 0x80}, {(byte) 0xff, '\r'}};
        for (int length : lengths) {
            for (byte[] separator : separators) {
                String result;
                try {
                    result = hex(Base64.getMimeEncoder(length, separator).encodeToString(sample)
                        .getBytes(StandardCharsets.ISO_8859_1));
                } catch (IllegalArgumentException e) {
                    result = "!" + e.getMessage();
                }
                System.out.printf("M\t%d\t%s\t%s\t%s%n", length, hex(separator), hex(sample), result);
            }
        }
    }
}
