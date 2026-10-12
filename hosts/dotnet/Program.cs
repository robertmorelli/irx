// irx host: .NET Regex. argv[0] = interp | compiled | nonbacktracking, argv[1] = mode.
using System; using System.IO; using System.Text; using System.Text.Json; using System.Text.RegularExpressions;
var engine = args.Length > 0 ? args[0] : "interp";
var mode = args.Length > 1 ? args[1] : "default";
int rep = (mode == "repeat" || mode == "tierup") ? 2 : 1;
// Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
bool wide = mode == "lspan" || mode == "lcapture";
// aspan (sticky): the match must start at the offset: \G(?:p) with Regex.Match(s, startat).
bool sticky = mode == "aspan";
bool isSpan = mode == "span" || mode == "lspan" || mode == "ospan" || sticky, isCap = mode == "capture" || mode == "lcapture";
string X = wide ? "x4" : "x2";
string NONE = new string('f', wide ? 8 : 4);
string Failed(int b, int rest) => (wide ? "fffe" + b.ToString("x4") : "fe" + b.ToString("x2")) + new string('0', (wide ? 4 : 2) * rest);
var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true };
var stdin = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
stdout.WriteLine($"ready dotnet-{Environment.Version}-{engine} mode={mode}");
var xesc = new Regex(@"\\x\{([0-9A-Fa-f]+)\}");
// Per-match time limit; a match that exceeds it is reported as unsupported (a resource limit,
// not a wrong answer), so one catastrophic case doesn't cost its whole batch.
var Limit = TimeSpan.FromMilliseconds(250);
string line;
while ((line = stdin.ReadLine()) != null) {
    if (line.Trim().Length == 0) continue;
    // Lone surrogate escapes (valid JSON, rejected by GetString) become a marker.
    line = Regex.Replace(line, @"\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\u[dD][c-fC-F])|(?<![0-9a-fA-F]{2})\\u[dD][c-fC-F][0-9a-fA-F]{2}", @"\uFFFF");
    using var doc = JsonDocument.Parse(line);
    var root = doc.RootElement;
    var sb = new StringBuilder(root[0].GetRawText()).Append(' ');
    foreach (var c in root[1].EnumerateArray()) {
        string f, a, r, p;
        try { f = c[0].GetString(); a = c[1].GetString(); r = c[2].GetString(); p = c[3].GetString(); }
        catch (InvalidOperationException) { sb.Append(isSpan ? Failed(0x40, 2) : isCap ? Failed(0x40, 26) : "40"); continue; } // undecodable (lone surrogate)
        // ospan: "<flags>@<a>,<r>" = search start per subject (UTF-16, Regex.Match(s, startat))
        int[] starts = { 0, 0 };
        int at = f.IndexOf('@');
        if (at >= 0) { var offs = f.Substring(at + 1).Split(','); starts[0] = int.Parse(offs[0]); starts[1] = int.Parse(offs[1]); f = f.Substring(0, at); }
        bool lone = (a + r + p).Contains('\uFFFF');
        foreach (var s in new[] { a, r, p }) for (int i = 0; i < s.Length; i++) {
            if (char.IsHighSurrogate(s[i]) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1])) { i++; continue; }
            if (char.IsSurrogate(s[i])) lone = true;
        }
        if (lone) { sb.Append(isSpan ? Failed(0x40, 2) : isCap ? Failed(0x40, 26) : "40"); continue; }
        // \x{H} -> raw char; surrogate halves (UTF-16 dialect literals) become single chars.
        p = xesc.Replace(p, m => { int cp = Convert.ToInt32(m.Groups[1].Value, 16); return cp >= 0xD800 && cp <= 0xDFFF ? ((char)cp).ToString() : char.ConvertFromUtf32(cp); });
        var o = RegexOptions.CultureInvariant;
        if (f.Contains('i')) o |= RegexOptions.IgnoreCase;
        if (f.Contains('m')) o |= RegexOptions.Multiline;
        if (f.Contains('s')) o |= RegexOptions.Singleline;
        if (engine == "compiled") o |= RegexOptions.Compiled;
        if (engine == "nonbacktracking") o |= RegexOptions.NonBacktracking;
        Regex re;
        if (isCap) { // whole match + groups 1..6, UTF-16 offsets (src/capture.zig)
            try { re = new Regex(p, o, Limit); } catch (Exception) { sb.Append(Failed(4, 26)); continue; }
            try {
                var sp = new StringBuilder();
                foreach (var s in new[] { a, r }) {
                    var m = re.Match(s);
                    // .NET numbers named groups after unnamed ones; irx names them g<printed number>,
                    // so put every group back in opening-parenthesis order.
                    var byNum = new System.Collections.Generic.Dictionary<int, Group>();
                    int unnamed = 0;
                    foreach (var gn in re.GetGroupNames()) {
                        int num = re.GroupNumberFromName(gn);
                        if (num == 0) continue;
                        if (gn.Length > 1 && gn[0] == 'g' && int.TryParse(gn.Substring(1), out var printed)) byNum[printed] = m.Groups[num];
                    }
                    // Unnamed groups fill the printed numbers not taken by named ones, in order.
                    for (int num = 1, next = 1; num < m.Groups.Count; num++) {
                        if (int.TryParse(re.GroupNameFromNumber(num), out _)) { while (byNum.ContainsKey(next)) next++; byNum[next] = m.Groups[num]; next++; unnamed++; }
                    }
                    sp.Append(m.Success ? m.Index.ToString(X) + (m.Index + m.Length).ToString(X) : NONE);
                    for (int g = 1; g <= 6; g++) sp.Append(m.Success && byNum.TryGetValue(g, out var gr) && gr.Success ? gr.Index.ToString(X) + (gr.Index + gr.Length).ToString(X) : NONE);
                }
                sb.Append(sp);
            } catch (RegexMatchTimeoutException) { sb.Append(Failed(0x40, 26)); } catch (Exception) { sb.Append(Failed(8, 26)); }
            continue;
        }
        if (isSpan) { // unanchored search, UTF-16 offsets (src/span.zig)
            try { re = new Regex(sticky ? @"\G(?:" + p + ")" : p, o, Limit); } catch (Exception) { sb.Append(Failed(4, 2)); continue; }
            try {
                var sp = new StringBuilder();
                foreach (var (s, k) in new[] { (a, starts[0]), (r, starts[1]) }) { var m = re.Match(s, k); sp.Append(m.Success ? m.Index.ToString(X) + (m.Index + m.Length).ToString(X) : NONE); }
                sb.Append(sp);
            } catch (RegexMatchTimeoutException) { sb.Append(Failed(0x40, 2)); } catch (Exception) { sb.Append(Failed(8, 2)); }
            continue;
        }
        try { re = new Regex(@"\A(?:" + p + @")\z", o, Limit); } catch (Exception) { sb.Append("04"); continue; }
        int bits = 0;
        try {
            for (int k = 0; k < rep; k++) {
                if (re.IsMatch(a)) bits |= 1 << (4 * k);
                if (re.IsMatch(r)) bits |= 2 << (4 * k);
            }
        } catch (RegexMatchTimeoutException) { bits = 0x40; } catch (Exception) { bits = 8; }
        sb.Append(bits.ToString("x2"));
    }
    stdout.WriteLine(sb.ToString());
}
