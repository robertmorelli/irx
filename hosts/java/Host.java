// irx host: java.util.regex. Perl-dialect patterns (\x{H} is native Java syntax).
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.*;

public class Host {
    static int pos; static String L; static boolean lone;
    static String str() {
        StringBuilder sb = new StringBuilder(); pos++;
        while (L.charAt(pos) != '"') {
            char c = L.charAt(pos);
            if (c == '\\') {
                c = L.charAt(++pos);
                switch (c) {
                    case 'n': sb.append('\n'); break; case 'r': sb.append('\r'); break; case 't': sb.append('\t'); break;
                    case 'b': sb.append('\b'); break; case 'f': sb.append('\f'); break;
                    case 'u': { char u = (char) Integer.parseInt(L.substring(pos + 1, pos + 5), 16); pos += 4; sb.append(u); break; }
                    default: sb.append(c);
                }
            } else sb.append(c);
            pos++;
        }
        pos++;
        return sb.toString();
    }
    static boolean hasLone(String s) {
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (Character.isHighSurrogate(c)) { if (i + 1 < s.length() && Character.isLowSurrogate(s.charAt(i + 1))) { i++; continue; } return true; }
            if (Character.isLowSurrogate(c)) return true;
        }
        return false;
    }
    public static void main(String[] args) throws IOException {
        String mode = args.length > 0 ? args[0] : "default";
        int rep = (mode.equals("repeat") || mode.equals("tierup")) ? 2 : 1;
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8), 1 << 20);
        PrintStream out = new PrintStream(new FileOutputStream(FileDescriptor.out), false, "UTF-8");
        out.println("ready java-" + System.getProperty("java.version") + " mode=" + mode); out.flush();
        while ((L = in.readLine()) != null) {
            if (L.isBlank()) continue;
            int comma = L.indexOf(',');
            String seq = L.substring(1, comma);
            pos = comma + 2;
            StringBuilder res = new StringBuilder(seq).append(' ');
            while (L.charAt(pos) != ']') {
                if (L.charAt(pos) == ',') { pos++; continue; }
                pos++;
                String f = str(); pos++; String a = str(); pos++; String r = str(); pos++; String p = str(); pos++;
                // ospan: "<flags>@<a>,<r>" = search start per subject (UTF-16, Matcher.find(int))
                int[] starts = { 0, 0 };
                int at = f.indexOf('@');
                if (at >= 0) { String[] o = f.substring(at + 1).split(","); starts[0] = Integer.parseInt(o[0]); starts[1] = Integer.parseInt(o[1]); f = f.substring(0, at); }
                // Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
                boolean wide = mode.equals("lspan") || mode.equals("lcapture");
                boolean span = mode.equals("span") || mode.equals("lspan") || mode.equals("ospan"), capture = mode.equals("capture") || mode.equals("lcapture");
                String PF = wide ? "%04x%04x" : "%02x%02x", NONE = wide ? "ffffffff" : "ffff";
                java.util.function.BiFunction<Integer, Integer, String> failed = (b, rest) -> (wide ? String.format("fffe%04x", b) : String.format("fe%02x", b)) + "0".repeat((wide ? 4 : 2) * rest);
                if (hasLone(a) || hasLone(r) || hasLone(p)) { res.append(span ? failed.apply(0x40, 2) : capture ? failed.apply(0x40, 26) : "40"); continue; }
                int fl = Pattern.UNICODE_CASE | Pattern.UNICODE_CHARACTER_CLASS;
                if (f.indexOf('i') >= 0) fl |= Pattern.CASE_INSENSITIVE;
                if (f.indexOf('m') >= 0) fl |= Pattern.MULTILINE;
                if (f.indexOf('s') >= 0) fl |= Pattern.DOTALL;
                Pattern pat;
                if (capture) { // whole match + groups 1..6 per subject, UTF-16 offsets (src/capture.zig)
                    try { pat = Pattern.compile(p, fl); } catch (Exception e) { res.append(failed.apply(4, 26)); continue; }
                    StringBuilder sp = new StringBuilder();
                    try {
                        for (String s : new String[] { a, r }) {
                            java.util.regex.Matcher m = pat.matcher(s);
                            boolean ok = m.find();
                            for (int g = 0; g <= 6; g++) sp.append(ok && g <= m.groupCount() && m.start(g) >= 0 ? String.format(PF, m.start(g), m.end(g)) : NONE);
                        }
                        res.append(sp);
                    } catch (StackOverflowError t) { res.append(failed.apply(0x40, 26)); } catch (Throwable t) { res.append(failed.apply(8, 26)); }
                    continue;
                }
                if (span) { // unanchored search, UTF-16 offsets (src/span.zig)
                    try { pat = Pattern.compile(p, fl); } catch (Exception e) { res.append(failed.apply(4, 2)); continue; }
                    StringBuilder sp = new StringBuilder();
                    try {
                        for (int k = 0; k < 2; k++) {
                            java.util.regex.Matcher m = pat.matcher(k == 0 ? a : r);
                            sp.append(m.find(starts[k]) ? String.format(PF, m.start(), m.end()) : NONE);
                        }
                        res.append(sp);
                    } catch (StackOverflowError t) { res.append(failed.apply(0x40, 2)); } catch (Throwable t) { res.append(failed.apply(8, 2)); }
                    continue;
                }
                try { pat = Pattern.compile("\\A(?:" + p + ")\\z", fl); } catch (Exception e) { res.append("04"); continue; }
                int bits = 0;
                try {
                    for (int k = 0; k < rep; k++) {
                        if (pat.matcher(a).find()) bits |= 1 << (4 * k);
                        if (pat.matcher(r).find()) bits |= 2 << (4 * k);
                    }
                } catch (StackOverflowError t) { bits = 0x40; } catch (Throwable t) { bits = 8; }
                res.append(String.format("%02x", bits));
            }
            out.println(res); out.flush();
        }
    }
}
