<?php
// irx host: PHP preg_* (PCRE2, UTF + UCP). Perl-dialect patterns pass through unchanged.
$mode = $argv[1] ?? "default"; $rep = in_array($mode, ["repeat", "tierup"]) ? 2 : 1;
echo "ready php-pcre-" . PCRE_VERSION . " mode=$mode\n"; fflush(STDOUT);
while (($line = fgets(STDIN)) !== false) {
    if (trim($line) === "") continue;
    // Lone surrogate escapes (valid JSON, rejected by json_decode) become a marker.
    $line = preg_replace('/\\\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\\\u[dD][c-fC-F])|(?<![0-9a-fA-F]{2})\\\\u[dD][c-fC-F][0-9a-fA-F]{2}/', '\\\\uFFFF', $line);
    $msg = json_decode($line, true);
    if ($msg === null) { fwrite(STDERR, "bad request\n"); exit(1); }
    [$seq, $cases] = $msg;
    $out = "";
    foreach ($cases as [$flags, $a, $r, $pat]) {
        if (str_contains($a . $r . $pat, "\u{FFFF}")) { $out .= $mode === "span" ? "fe400000" : ($mode === "capture" ? "fe40" . str_repeat("00", 26) : "40"); continue; }
        $m = "u" . (str_contains($flags, "i") ? "i" : "") . (str_contains($flags, "m") ? "m" : "") . (str_contains($flags, "s") ? "s" : "");
        if ($mode === "capture") { // whole match + groups 1..6 per subject, byte offsets (src/capture.zig)
            $re = "\x01" . $pat . "\x01" . $m; $s = "";
            foreach ([$a, $r] as $j => $subj) {
                $res = @preg_match($re, $subj, $mm, PREG_OFFSET_CAPTURE | PREG_UNMATCHED_AS_NULL);
                if ($res === false) { $s = ((preg_last_error() === PREG_INTERNAL_ERROR && $j == 0) ? "fe04" : "fe08") . str_repeat("00", 26); break; }
                for ($g = 0; $g < 7; $g++) {
                    $x = $mm[$g] ?? null;
                    $s .= ($res === 1 && $x !== null && $x[0] !== null && $x[1] >= 0) ? sprintf("%02x%02x", $x[1], $x[1] + strlen($x[0])) : "ffff";
                }
            }
            $out .= $s; continue;
        }
        if ($mode === "span") { // unanchored search, byte offsets (src/span.zig)
            $re = "\x01" . $pat . "\x01" . $m; $s = "";
            foreach ([$a, $r] as $j => $subj) {
                $res = @preg_match($re, $subj, $mm, PREG_OFFSET_CAPTURE);
                if ($res === false) { $s = (preg_last_error() === PREG_INTERNAL_ERROR && $j == 0) ? "fe040000" : "fe080000"; break; }
                $s .= $res === 1 ? sprintf("%02x%02x", $mm[0][1], $mm[0][1] + strlen($mm[0][0])) : "ffff";
            }
            $out .= $s; continue;
        }
        $re = "\x01\\A(?:" . $pat . ")\\z\x01" . $m;
        $bits = 0;
        for ($k = 0; $k < $rep; $k++) {
            foreach ([$a, $r] as $j => $s) {
                $res = @preg_match($re, $s);
                if ($res === false) { $bits = preg_last_error() === PREG_INTERNAL_ERROR && $k == 0 && $j == 0 ? 4 : 8; break 2; }
                if ($res === 1) $bits |= (1 << $j) << (4 * $k);
            }
        }
        $out .= sprintf("%02x", $bits);
    }
    echo "$seq $out\n"; fflush(STDOUT);
}
