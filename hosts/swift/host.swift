// irx host: Swift Regex (argv[1] = "swift") or ICU NSRegularExpression (argv[1] = "icu").
import Foundation
setvbuf(stdout, nil, _IOLBF, 0)
let engine = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "swift"
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "default"
let rep = (mode == "repeat" || mode == "tierup") ? 2 : 1
print("ready \(engine == "icu" ? "icu-nsregex" : "swift-regex-scalar") mode=\(mode)")
func hasLone(_ s: String) -> Bool { s.unicodeScalars.contains { $0.value == 0xFFFF } }
/// Minimal parser for the irx request line (Foundation's JSON decoding drops U+FEFF).
func parseRequest(_ line: String) -> (String, [[String]])? {
    let u = Array(line.utf16); var i = 0
    func str() -> String? {
        guard u[i] == 0x22 else { return nil }; i += 1
        var scalars = String.UnicodeScalarView()
        while i < u.count && u[i] != 0x22 {
            var c = UInt32(u[i])
            if c == 0x5C {
                i += 1; let e = u[i]
                switch e {
                case 0x6E: c = 0x0A; case 0x72: c = 0x0D; case 0x74: c = 0x09; case 0x62: c = 0x08; case 0x66: c = 0x0C
                case 0x75:
                    c = UInt32(String(decoding: u[(i + 1)...(i + 4)], as: UTF16.self), radix: 16)!; i += 4
                    if (0xD800...0xDBFF).contains(c), i + 6 < u.count, u[i + 1] == 0x5C, u[i + 2] == 0x75,
                       let d = UInt32(String(decoding: u[(i + 3)...(i + 6)], as: UTF16.self), radix: 16), (0xDC00...0xDFFF).contains(d) {
                        c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00); i += 6
                    } else if (0xD800...0xDFFF).contains(c) { c = 0xFFFF }
                default: c = UInt32(e)
                }
            }
            scalars.append(Unicode.Scalar(c)!); i += 1
        }
        i += 1; return String(scalars)
    }
    guard u.first == 0x5B, let comma = u.firstIndex(of: 0x2C) else { return nil }
    let seq = String(decoding: u[1..<comma], as: UTF16.self); i = comma + 2
    var cases: [[String]] = []
    while i < u.count && u[i] != 0x5D {
        if u[i] == 0x2C { i += 1; continue }
        i += 1; var f: [String] = []
        for k in 0..<4 { guard let s = str() else { return nil }; f.append(s); if k < 3 { i += 1 } }
        i += 1; cases.append(f)
    }
    return (seq, cases)
}
/// Span mode: unanchored search; UTF-16 offsets of the first match in A and R (src/span.zig).
func spanCase(_ f: String, _ a: String, _ r: String, _ p: String) -> String {
    func hx(_ n: Int) -> String { String(format: "%02x", n) }
    var res = ""
    if engine == "icu" {
        var o: NSRegularExpression.Options = []
        if f.contains("i") { o.insert(.caseInsensitive) }
        if f.contains("m") { o.insert(.anchorsMatchLines) }
        if f.contains("s") { o.insert(.dotMatchesLineSeparators) }
        guard let re = try? NSRegularExpression(pattern: p, options: o) else { return "fe040000" }
        for s in [a, r] {
            if let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) { res += hx(m.range.location) + hx(m.range.location + m.range.length) } else { res += "ffff" }
        }
        return res
    }
    guard var re = try? Regex(p) else { return "fe040000" }
    re = re.matchingSemantics(.unicodeScalar).wordBoundaryKind(.simple)
    if f.contains("i") { re = re.ignoresCase() }
    if f.contains("m") { re = re.anchorsMatchLineEndings() }
    if f.contains("s") { re = re.dotMatchesNewlines() }
    for s in [a, r] {
        guard let mm = try? re.firstMatch(in: s) else { res += "ffff"; continue }
        let st = s.utf16.distance(from: s.startIndex, to: mm.range.lowerBound)
        res += hx(st) + hx(st + s.utf16.distance(from: mm.range.lowerBound, to: mm.range.upperBound))
    }
    return res
}
while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    guard let (seq, cases) = parseRequest(line) else { FileHandle.standardError.write("bad request\n".data(using: .utf8)!); exit(1) }
    var out = "\(seq) "
    for c in cases {
        let f = c[0], a = c[1], r = c[2], p = c[3]
        if hasLone(a) || hasLone(r) || hasLone(p) { out += mode == "span" ? "fe400000" : "40"; continue }
        if mode == "span" { out += spanCase(f, a, r, p); continue }
        let src = "\\A(?:" + p + ")\\z"
        var bits = 0
        if engine == "icu" {
            var o: NSRegularExpression.Options = []
            if f.contains("i") { o.insert(.caseInsensitive) }
            if f.contains("m") { o.insert(.anchorsMatchLines) }
            if f.contains("s") { o.insert(.dotMatchesLineSeparators) }
            guard let re = try? NSRegularExpression(pattern: src, options: o) else { out += "04"; continue }
            for k in 0..<rep {
                for (j, s) in [a, r].enumerated() {
                    if re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { bits |= (1 << j) << (4 * k) }
                }
            }
        } else {
            // Unicode-scalar semantics and simple word boundaries: the modes irx models.
            guard var re = try? Regex(src) else { out += "04"; continue }
            re = re.matchingSemantics(.unicodeScalar).wordBoundaryKind(.simple)
            if f.contains("i") { re = re.ignoresCase() }
            if f.contains("m") { re = re.anchorsMatchLineEndings() }
            if f.contains("s") { re = re.dotMatchesNewlines() }
            for k in 0..<rep {
                for (j, s) in [a, r].enumerated() {
                    if (try? re.firstMatch(in: s)) != nil { bits |= (1 << j) << (4 * k) }
                }
            }
        }
        out += String(format: "%02x", bits)
    }
    print(out)
}
