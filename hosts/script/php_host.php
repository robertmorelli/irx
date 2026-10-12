<?php
// irx host: PHP preg_* (PCRE2, UTF + UCP). Perl-dialect patterns pass through unchanged.
$mode = $argv[1] ?? "default"; $rep = in_array($mode, ["repeat", "tierup"]) ? 2 : 1;
// Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
$wide = in_array($mode, ["lspan", "lcapture"]); $D = $wide ? 4 : 2; $NONE = str_repeat("f", 2 * $D);
$sticky = $mode === "aspan"; // the match must start at the offset: the A modifier with the offset
$isSpan = in_array($mode, ["span", "lspan", "ospan", "aspan"]); $isCap = in_array($mode, ["capture", "lcapture"]);
function pair($s, $e) { global $D; return sprintf("%0{$D}x%0{$D}x", $s, $e); }
function failed($b, $rest) { global $wide, $D; return ($wide ? sprintf("fffe%04x", $b) : sprintf("fe%02x", $b)) . str_repeat("0", $D * $rest); }
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
        if ($mode === "bench") { // Shootout 2: "<flags>#<reps>"; the first preg_match compiles (PCRE cache), then timed searches
            [$flags, $n] = array_pad(explode("#", $flags, 2), 2, "1"); $n = max(1, intval($n));
            if (str_contains($a . $r . $pat, "\u{FFFF}")) { $out .= "fe40" . str_repeat("0", 36); continue; }
            $re = "\x01" . $pat . "\x01u" . (str_contains($flags, "i") ? "i" : "") . (str_contains($flags, "m") ? "m" : "") . (str_contains($flags, "s") ? "s" : "");
            $t0 = hrtime(true); $ok = @preg_match($re, ""); $tc = hrtime(true) - $t0;
            if ($ok === false) { $out .= "fe04" . str_repeat("0", 36); continue; }
            $ma = @preg_match($re, $a); $mr = @preg_match($re, $r);
            if ($ma === false || $mr === false) { $out .= "fe08" . str_repeat("0", 36); continue; }
            $t1 = hrtime(true); for ($i = 0; $i < $n; $i++) preg_match($re, $a);
            $t2 = hrtime(true); for ($i = 0; $i < $n; $i++) preg_match($re, $r);
            $t3 = hrtime(true);
            $out .= sprintf("%02x%012x%012x%012x", $ma | ($mr << 1), $tc, $t2 - $t1, $t3 - $t2); continue;
        }
        // ospan: "<flags>@<a>,<r>" = search start per subject (bytes)
        $starts = [0, 0];
        if (($at = strpos($flags, "@")) !== false) { $starts = array_map("intval", explode(",", substr($flags, $at + 1))); $flags = substr($flags, 0, $at); }
        if (str_contains($a . $r . $pat, "\u{FFFF}")) { $out .= $isSpan ? failed(0x40, 2) : ($isCap ? failed(0x40, 26) : "40"); continue; }
        $m = "u" . (str_contains($flags, "i") ? "i" : "") . (str_contains($flags, "m") ? "m" : "") . (str_contains($flags, "s") ? "s" : "");
        if ($isCap) { // whole match + groups 1..6 per subject, byte offsets (src/capture.zig)
            $re = "\x01" . $pat . "\x01" . $m; $s = "";
            foreach ([$a, $r] as $j => $subj) {
                $res = @preg_match($re, $subj, $mm, PREG_OFFSET_CAPTURE | PREG_UNMATCHED_AS_NULL);
                if ($res === false) { $s = failed((preg_last_error() === PREG_INTERNAL_ERROR && $j == 0) ? 4 : 8, 26); break; }
                for ($g = 0; $g < 7; $g++) {
                    $x = $mm[$g] ?? null;
                    $s .= ($res === 1 && $x !== null && $x[0] !== null && $x[1] >= 0) ? pair($x[1], $x[1] + strlen($x[0])) : $NONE;
                }
            }
            $out .= $s; continue;
        }
        if ($isSpan) { // unanchored search, byte offsets (src/span.zig)
            $re = "\x01" . $pat . "\x01" . $m . ($sticky ? "A" : ""); $s = "";
            foreach ([$a, $r] as $j => $subj) {
                $res = @preg_match($re, $subj, $mm, PREG_OFFSET_CAPTURE, $starts[$j]);
                if ($res === false) { $s = failed((preg_last_error() === PREG_INTERNAL_ERROR && $j == 0) ? 4 : 8, 2); break; }
                $s .= $res === 1 ? pair($mm[0][1], $mm[0][1] + strlen($mm[0][0])) : $NONE;
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
