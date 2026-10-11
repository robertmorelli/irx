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
# (ff = no match), or fe + bits when the case fails (see src/span.zig).
sub span_case {
    my ($c) = @_;
    my ($flags, $a, $r, $src) = @$c;
    return 'fe040000' if $src =~ /\(\?\??\{/;
    my $mods = '';
    $mods .= 'i' if $flags =~ /i/;
    $mods .= 'm' if $flags =~ /m/;
    $mods .= 's' if $flags =~ /s/;
    $mods .= 'u' if $flags =~ /[uv]/;
    my $re = eval { qr/(?^$mods:$src)/ };
    return 'fe040000' unless defined $re;
    my $out = '';
    my $ok = eval {
        for my $s ($a, $r) {
            $out .= ($s =~ $re) ? sprintf('%02x%02x', $-[0], $+[0]) : 'ffff';
        }
        1;
    };
    return 'fe080000' unless $ok;
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
        print $seq, ' ', ($mode eq 'span' ? 'fe400000' : '40') x $n, "\n";
        next;
    }
    my ($seq, $cases) = @$msg;
    if ($mode eq 'span') { print $seq, ' ', join('', map { span_case($_) } @$cases), "\n"; next; }
    print $seq, ' ', join('', map { sprintf '%02x', run_case($_) } @$cases), "\n";
}
