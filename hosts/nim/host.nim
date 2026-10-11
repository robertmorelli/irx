## irx host: nim-regex (re2 API). Perl-dialect patterns; inline flags (?ims).
import std/[json, strutils, strformat, os]
import regex

let mode = if paramCount() > 0: paramStr(1) else: "default"
let rep = if mode in ["repeat", "tierup"]: 2 else: 1
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
    let f = c[0].getStr; let a = c[1].getStr; let r = c[2].getStr; let p = c[3].getStr
    if "\uFFFF" in a or "\uFFFF" in r or "\uFFFF" in p:
      outp.add(if mode == "span": "fe400000" else: "40"); continue
    var fl = ""
    for ch in "ims":
      if ch in f: fl.add ch
    if mode == "span":
      # Unanchored search, byte offsets of the first match (src/span.zig).
      var sp = ""
      try:
        let rx = re2((if fl.len > 0: "(?" & fl & ")" else: "") & p)
        for s in [a, r]:
          var m: RegexMatch2
          if find(s, rx, m):
            sp.add toHex(m.boundaries.a, 2).toLowerAscii & toHex(m.boundaries.b + 1, 2).toLowerAscii
          else: sp.add "ffff"
      except RegexError:
        sp = "fe040000"
      except CatchableError, Defect:
        sp = "fe080000"
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
