#!/usr/bin/env perl
# irx driver for Perl's regex engine. Same line protocol as driver.js:
#   request : [batch_seq, [[flags, A, R, regex], ...]]   (one JSON line)
#   response: "<batch_seq> <2 hex digits per case>"
# Bits: 0 A matches, 1 R matches, 2 compile error, 3 runtime exception,
#       4/5 second A/R run (mode "repeat" only), 6 unsupported/skipped, 7 reserved.
# Full match uses \A(?:r)\z, which /m does not affect.
use strict;
use warnings;
no warnings 'regexp';
use JSON::PP ();

$| = 1;    # flush every response line
my $mode   = @ARGV ? $ARGV[0] : 'perl';
my $repeat = $mode eq 'repeat';
my $json   = JSON::PP->new->utf8->allow_nonref;

binmode STDIN,  ':raw';
binmode STDOUT, ':raw';

sub run_case {
    my ($c) = @_;
    my ($flags, $a, $r, $src) = @$c;
    # Never allow embedded code; the generator does not emit it.
    return 0x04 if $src =~ /\(\?\??\{/;
    my $mods = '';
    $mods .= 'i' if $flags =~ /i/;
    $mods .= 'm' if $flags =~ /m/;
    $mods .= 's' if $flags =~ /s/;
    $mods .= 'u' if $flags =~ /[uv]/;
    my $re = eval { qr/(?^$mods:\A(?:$src)\z)/ };
    return 0x04 unless defined $re;
    my $bits = 0;
    my $ok = eval {
        $bits |= 0x01 if $a =~ $re;
        $bits |= 0x02 if $r =~ $re;
        if ($repeat) {
            $bits |= 0x10 if $a =~ $re;
            $bits |= 0x20 if $r =~ $re;
        }
        1;
    };
    return 0x08 unless $ok;
    return $bits;
}

# Span mode: unanchored search; code-point offsets of the first match in A and R
# (ff = no match), or fe + bits when the case fails (see src/span.zig). Long modes
# (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
my $wide = ($mode eq 'lspan' || $mode eq 'lcapture') ? 1 : 0;
my $PF = $wide ? '%04x%04x' : '%02x%02x';
my $NONE = $wide ? 'ffffffff' : 'ffff';
sub span_fail { $wide ? sprintf('fffe%04x', $_[0]) . ('0' x 8) : sprintf('fe%02x0000', $_[0]) }
sub cap_fail { $wide ? sprintf('fffe%04x', $_[0]) . ('0000' x 26) : sprintf('fe%02x', $_[0]) . ('00' x 26) }
sub span_case {
    my ($c) = @_;
    my ($flags, $a, $r, $src) = @$c;
    return span_fail(0x04) if $src =~ /\(\?\??\{/;
    my $mods = '';
    $mods .= 'i' if $flags =~ /i/;
    $mods .= 'm' if $flags =~ /m/;
    $mods .= 's' if $flags =~ /s/;
    $mods .= 'u' if $flags =~ /[uv]/;
    my $re = eval { qr/(?^$mods:$src)/ };
    return span_fail(0x04) unless defined $re;
    my $out = '';
    my $ok = eval {
        for my $s ($a, $r) {
            $out .= ($s =~ $re) ? sprintf($PF, $-[0], $+[0]) : $NONE;
        }
        1;
    };
    return span_fail(0x08) unless $ok;
    return $out;
}

# Capture mode: whole match then groups 1..6 per subject (ffff = unset; src/capture.zig).
sub capture_case {
    my ($c) = @_;
    my ($flags, $a, $r, $src) = @$c;
    my $fail = \&cap_fail;
    return $fail->(0x04) if $src =~ /\(\?\??\{/;
    my $mods = '';
    $mods .= 'i' if $flags =~ /i/;
    $mods .= 'm' if $flags =~ /m/;
    $mods .= 's' if $flags =~ /s/;
    $mods .= 'u' if $flags =~ /[uv]/;
    my $re = eval { qr/(?^$mods:$src)/ };
    return $fail->(0x04) unless defined $re;
    my $out = '';
    my $ok = eval {
        for my $s ($a, $r) {
            if ($s =~ $re) {
                for my $g (0 .. 6) {
                    $out .= ($g <= $#- && defined $-[$g]) ? sprintf($PF, $-[$g], $+[$g]) : $NONE;
                }
            } else { $out .= $NONE x 7 }
        }
        1;
    };
    return $fail->(0x08) unless $ok;
    return $out;
}

print "ready perl $^V mode=$mode\n";
while (defined(my $line = <STDIN>)) {
    chomp $line;
    next if $line eq '';
    my $msg = eval { $json->decode($line) };
    unless (defined $msg) {
        # Lone surrogates (JS-only) cannot be decoded; report the batch as unsupported.
        # Count cases on a copy with surrogate escapes neutralised.
        (my $tmp = $line) =~ s/\\u[dD][89a-fA-F][0-9a-fA-F]{2}/?/g;
        my $m = eval { $json->decode($tmp) };
        my ($seq, $n) = $m ? ($m->[0], scalar @{ $m->[1] }) : (0, 0);
        print $seq, ' ', ($mode =~ /span$/ ? span_fail(0x40) : $mode =~ /capture$/ ? cap_fail(0x40) : '40') x $n, "\n";
        next;
    }
    my ($seq, $cases) = @$msg;
    if ($mode eq 'span' || $mode eq 'lspan') { print $seq, ' ', join('', map { span_case($_) } @$cases), "\n"; next; }
    if ($mode eq 'capture' || $mode eq 'lcapture') { print $seq, ' ', join('', map { capture_case($_) } @$cases), "\n"; next; }
    print $seq, ' ', join('', map { sprintf '%02x', run_case($_) } @$cases), "\n";
}
