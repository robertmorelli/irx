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
        if (str_contains($a . $r . $pat, "\u{FFFF}")) { $out .= "40"; continue; }
        $m = "u" . (str_contains($flags, "i") ? "i" : "") . (str_contains($flags, "m") ? "m" : "") . (str_contains($flags, "s") ? "s" : "");
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
