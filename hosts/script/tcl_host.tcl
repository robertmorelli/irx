# irx host: Tcl ARE (regexp). \x{H} escapes become raw chars. Flags: i -> -nocase,
# m -> -line, s: Tcl's . matches newline by default unless -linestop.
fconfigure stdout -buffering line -translation lf
fconfigure stdin -encoding utf-8 -translation lf
set mode [expr {[llength $argv] ? [lindex $argv 0] : "default"}]
set rep [expr {$mode in {repeat tierup} ? 2 : 1}]
puts "ready tcl-[info patchlevel] mode=$mode"
proc jstr {s idx} {
    # minimal JSON string parser; returns {value newidx}
    upvar $idx i
    incr i
    set out ""
    while {[string index $s $i] ne "\""} {
        set c [string index $s $i]
        if {$c eq "\\"} {
            incr i; set c [string index $s $i]
            switch -- $c {
                n {append out "\n"} r {append out "\r"} t {append out "\t"} b {append out "\b"} f {append out "\f"}
                u { set h [string range $s [expr {$i+1}] [expr {$i+4}]]; incr i 4
                    scan $h %x cp
                    if {$cp >= 0xD800 && $cp <= 0xDBFF && [string range $s [expr {$i+1}] [expr {$i+2}]] eq "\\u"} {
                        scan [string range $s [expr {$i+3}] [expr {$i+6}]] %x lo; incr i 6
                        set cp [expr {0x10000 + (($cp - 0xD800) << 10) + ($lo - 0xDC00)}]
                    } elseif {$cp >= 0xD800 && $cp <= 0xDFFF} { set ::lone 1 }
                    append out [format %c $cp] }
                default {append out $c}
            }
        } else { append out $c }
        incr i
    }
    incr i
    return $out
}
while {[gets stdin line] >= 0} {
    if {[string trim $line] eq ""} continue
    regexp {^\[(\d+),} $line -> seq
    set i [expr {[string first ",\[" $line] + 2}]
    set out ""
    while {[string index $line $i] ne "\]"} {
        if {[string index $line $i] eq ","} { incr i; continue }
        incr i
        set ::lone 0
        set f [jstr $line i]; incr i; set a [jstr $line i]; incr i; set r [jstr $line i]; incr i; set p [jstr $line i]; incr i
        if {$::lone} { append out 40; continue }
        # Expand \x{H} escapes to raw characters without subst (patterns contain [ ]).
        set p2 ""
        while {[regexp -indices {\\x\{([0-9A-Fa-f]+)\}} $p all hex]} {
            append p2 [string range $p 0 [expr {[lindex $all 0] - 1}]]
            append p2 [format %c [expr 0x[string range $p {*}$hex]]]
            set p [string range $p [expr {[lindex $all 1] + 1}] end]
        }
        set p "$p2$p"
        set opts {}
        if {[string first i $f] >= 0} { lappend opts -nocase }
        if {[string first m $f] >= 0} { lappend opts -lineanchor }
        if {[string first s $f] < 0} { lappend opts -linestop }
        set re "^(?:$p)\$"
        if {[catch {regexp {*}$opts -- $re ""} err]} { append out 04; continue }
        set bits 0
        for {set k 0} {$k < $rep} {incr k} {
            if {[regexp {*}$opts -- $re $a]} { set bits [expr {$bits | (1 << (4*$k))}] }
            if {[regexp {*}$opts -- $re $r]} { set bits [expr {$bits | (2 << (4*$k))}] }
        }
        append out [format %02x $bits]
    }
    puts "$seq $out"
}
