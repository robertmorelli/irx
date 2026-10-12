// irx host: .NET Regex. argv[0] = interp | compiled | nonbacktracking, argv[1] = mode.
using System; using System.IO; using System.Text; using System.Text.Json; using System.Text.RegularExpressions;
var engine = args.Length > 0 ? args[0] : "interp";
var mode = args.Length > 1 ? args[1] : "default";
int rep = (mode == "repeat" || mode == "tierup") ? 2 : 1;
// Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
bool wide = mode == "lspan" || mode == "lcapture";
// aspan (sticky): the match must start at the offset: \G(?:p) with Regex.Match(s, startat).
System.Globalization.CultureInfo.CurrentCulture = System.Globalization.CultureInfo.InvariantCulture;
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
        // BMP code points as \uXXXX escapes (a raw space or \r would be ignored inside (?x:…)); astral ones raw.
        p = xesc.Replace(p, m => { int cp = Convert.ToInt32(m.Groups[1].Value, 16); return cp <= 0xFFFF ? "\\u" + cp.ToString("X4") : char.ConvertFromUtf32(cp); });
        // ecma: RegexOptions.ECMAScript, which allows only IgnoreCase, Multiline and Compiled (the
        // current culture is pinned to the invariant one instead); s has no ECMAScript form.
        bool ecma = engine == "ecma";
        if (ecma && f.Contains('s')) { sb.Append(isSpan ? Failed(0x40, 2) : isCap ? Failed(0x40, 26) : "40"); continue; }
        var o = ecma ? RegexOptions.ECMAScript : RegexOptions.CultureInvariant;
        if (f.Contains('i')) o |= RegexOptions.IgnoreCase;
        if (f.Contains('m')) o |= RegexOptions.Multiline;
        if (f.Contains('s')) o |= RegexOptions.Singleline;
        if (engine == "compiled") o |= RegexOptions.Compiled;
        if (engine == "nonbacktracking") o |= RegexOptions.NonBacktracking;
        if (mode == "bench") { // Shootout 2: "<flags>#<reps>"; compile once, timed IsMatch loops
            int hash = f.IndexOf('#'), nreps = hash >= 0 ? Math.Max(1, int.Parse(f.Substring(hash + 1))) : 1;
            var sw = System.Diagnostics.Stopwatch.StartNew();
            Regex br;
            try { br = new Regex(p, o, Limit); } catch (Exception) { sb.Append("fe04" + new string('0', 36)); continue; }
            long tc = sw.Elapsed.Ticks * 100;
            try {
                int bbits = (br.IsMatch(a) ? 1 : 0) | (br.IsMatch(r) ? 2 : 0);
                sw.Restart(); for (int k = 0; k < nreps; k++) br.IsMatch(a); long ta = sw.Elapsed.Ticks * 100;
                sw.Restart(); for (int k = 0; k < nreps; k++) br.IsMatch(r); long tr = sw.Elapsed.Ticks * 100;
                sb.Append(bbits.ToString("x2") + tc.ToString("x12") + ta.ToString("x12") + tr.ToString("x12"));
            } catch (RegexMatchTimeoutException) { sb.Append("fe40" + new string('0', 36)); } catch (Exception) { sb.Append("fe08" + new string('0', 36)); }
            continue;
        }
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
