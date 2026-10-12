## irx host: nim-regex (re2 API). Perl-dialect patterns; inline flags (?ims).
import std/[json, strutils, strformat, os, sequtils]
import regex

let mode = if paramCount() > 0: paramStr(1) else: "default"
let rep = if mode in ["repeat", "tierup"]: 2 else: 1
# Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
let wide = mode in ["lspan", "lcapture"]
let isSpan = mode in ["span", "lspan", "ospan"]
let isCap = mode in ["capture", "lcapture"]
let D = if wide: 4 else: 2
let NONE = "f".repeat(2 * D)
proc hx(n: int): string = toHex(n, D).toLowerAscii
proc failed(b, rest: int): string = (if wide: "fffe" else: "fe") & hx(b) & "0".repeat(D * rest)
echo &"ready nim-regex mode={mode}"
flushFile(stdout)
var line: string
while readLine(stdin, line):
  if line.strip.len == 0: continue
  # Lone surrogate escapes become a marker (\uFFFF) before parsing.
  var clean = line
  var i = 0
  while i + 5 < clean.len:
    if clean[i] == '\\' and clean[i+1] == '\\':
      i += 2; continue
    if clean[i] == '\\' and clean[i+1] == 'u' and clean[i+2] in "dD":
      let hi = clean[i+3] in "89abAB"
      let pairOk = hi and i + 11 < clean.len and clean[i+6] == '\\' and clean[i+7] == 'u' and clean[i+8] in "dD" and clean[i+9] in "cdefCDEF"
      if pairOk:
        i += 12; continue
      clean = clean[0 ..< i] & "\\uFFFF" & clean[i+6 .. ^1]
    inc i
  let msg = parseJson(clean)
  var outp = $msg[0].getInt & " "
  for c in msg[1]:
    var f = c[0].getStr; let a = c[1].getStr; let r = c[2].getStr; let p = c[3].getStr
    # ospan: "<flags>@<a>,<r>" = search start per subject (bytes)
    var starts = @[0, 0]
    let at = f.find('@')
    if at >= 0:
      starts = f[at + 1 .. ^1].split(',').mapIt(parseInt(it))
      f = f[0 ..< at]
    if "\uFFFF" in a or "\uFFFF" in r or "\uFFFF" in p:
      outp.add(if isSpan: failed(0x40, 2) elif isCap: failed(0x40, 26) else: "40"); continue
    var fl = ""
    for ch in "ims":
      if ch in f: fl.add ch
    if isCap:
      # Whole match + groups 1..6 per subject, byte offsets (src/capture.zig).
      var sp = ""
      try:
        let rx = re2((if fl.len > 0: "(?" & fl & ")" else: "") & p)
        for s in [a, r]:
          var m: RegexMatch2
          let ok = find(s, rx, m)
          for g in 0 .. 6:
            var b = -1 .. -2
            if ok:
              if g == 0: b = m.boundaries
              elif g - 1 < m.groupsCount: b = m.group(g - 1)
            if b.a < 0: sp.add NONE
            else: sp.add hx(b.a) & hx(b.b + 1)
      except RegexError:
        sp = failed(4, 26)
      except CatchableError, Defect:
        sp = failed(8, 26)
      outp.add sp
      continue
    if isSpan:
      # Unanchored search, byte offsets of the first match (src/span.zig).
      var sp = ""
      try:
        let rx = re2((if fl.len > 0: "(?" & fl & ")" else: "") & p)
        for k, s in [a, r]:
          var m: RegexMatch2
          if find(s, rx, m, starts[k]):
            sp.add hx(m.boundaries.a) & hx(m.boundaries.b + 1)
          else: sp.add NONE
      except RegexError:
        sp = failed(4, 2)
      except CatchableError, Defect:
        sp = failed(8, 2)
      outp.add sp
      continue
    let src = (if fl.len > 0: "(?" & fl & ")" else: "") & "\\A(?:" & p & ")\\z"
    var bits = 0
    try:
      let rx = re2(src)
      for k in 0 ..< rep:
        if a.contains(rx): bits = bits or (1 shl (4 * k))
        if r.contains(rx): bits = bits or (2 shl (4 * k))
    except RegexError:
      bits = 4
    except CatchableError, Defect:
      bits = 8
    outp.add toHex(bits, 2).toLowerAscii
  echo outp
  flushFile(stdout)
