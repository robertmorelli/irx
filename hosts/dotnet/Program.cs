// irx host: .NET Regex. argv[0] = interp | compiled | nonbacktracking, argv[1] = mode.
using System; using System.IO; using System.Text; using System.Text.Json; using System.Text.RegularExpressions;
var engine = args.Length > 0 ? args[0] : "interp";
var mode = args.Length > 1 ? args[1] : "default";
int rep = (mode == "repeat" || mode == "tierup") ? 2 : 1;
var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true };
var stdin = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
stdout.WriteLine($"ready dotnet-{Environment.Version}-{engine} mode={mode}");
var xesc = new Regex(@"\\x\{([0-9A-Fa-f]+)\}");
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
        catch (InvalidOperationException) { sb.Append(mode == "span" ? "fe400000" : mode == "capture" ? "fe40" + new string('0', 52) : "40"); continue; } // undecodable (lone surrogate)
        bool lone = (a + r + p).Contains('\uFFFF');
        foreach (var s in new[] { a, r, p }) for (int i = 0; i < s.Length; i++) {
            if (char.IsHighSurrogate(s[i]) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1])) { i++; continue; }
            if (char.IsSurrogate(s[i])) lone = true;
        }
        if (lone) { sb.Append(mode == "span" ? "fe400000" : mode == "capture" ? "fe40" + new string('0', 52) : "40"); continue; }
        // \x{H} -> raw char; surrogate halves (UTF-16 dialect literals) become single chars.
        p = xesc.Replace(p, m => { int cp = Convert.ToInt32(m.Groups[1].Value, 16); return cp >= 0xD800 && cp <= 0xDFFF ? ((char)cp).ToString() : char.ConvertFromUtf32(cp); });
        var o = RegexOptions.CultureInvariant;
        if (f.Contains('i')) o |= RegexOptions.IgnoreCase;
        if (f.Contains('m')) o |= RegexOptions.Multiline;
        if (f.Contains('s')) o |= RegexOptions.Singleline;
        if (engine == "compiled") o |= RegexOptions.Compiled;
        if (engine == "nonbacktracking") o |= RegexOptions.NonBacktracking;
        Regex re;
        if (mode == "capture") { // whole match + groups 1..6, UTF-16 offsets (src/capture.zig)
            try { re = new Regex(p, o, TimeSpan.FromSeconds(10)); } catch (Exception) { sb.Append("fe04" + new string('0', 52)); continue; }
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
                    sp.Append(m.Success ? m.Index.ToString("x2") + (m.Index + m.Length).ToString("x2") : "ffff");
                    for (int g = 1; g <= 6; g++) sp.Append(m.Success && byNum.TryGetValue(g, out var gr) && gr.Success ? gr.Index.ToString("x2") + (gr.Index + gr.Length).ToString("x2") : "ffff");
                }
                sb.Append(sp);
            } catch (Exception) { sb.Append("fe08" + new string('0', 52)); }
            continue;
        }
        if (mode == "span") { // unanchored search, UTF-16 offsets (src/span.zig)
            try { re = new Regex(p, o, TimeSpan.FromSeconds(10)); } catch (Exception) { sb.Append("fe040000"); continue; }
            try {
                var sp = new StringBuilder();
                foreach (var s in new[] { a, r }) { var m = re.Match(s); sp.Append(m.Success ? m.Index.ToString("x2") + (m.Index + m.Length).ToString("x2") : "ffff"); }
                sb.Append(sp);
            } catch (Exception) { sb.Append("fe080000"); }
            continue;
        }
        try { re = new Regex(@"\A(?:" + p + @")\z", o, TimeSpan.FromSeconds(10)); } catch (Exception) { sb.Append("04"); continue; }
        int bits = 0;
        try {
            for (int k = 0; k < rep; k++) {
                if (re.IsMatch(a)) bits |= 1 << (4 * k);
                if (re.IsMatch(r)) bits |= 2 << (4 * k);
            }
        } catch (Exception) { bits = 8; }
        sb.Append(bits.ToString("x2"));
    }
    stdout.WriteLine(sb.ToString());
}
