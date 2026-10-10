// irx host: Swift Regex (argv[1] = "swift") or ICU NSRegularExpression (argv[1] = "icu").
import Foundation
setvbuf(stdout, nil, _IOLBF, 0)
let engine = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "swift"
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "default"
let rep = (mode == "repeat" || mode == "tierup") ? 2 : 1
print("ready \(engine == "icu" ? "icu-nsregex" : "swift-regex") mode=\(mode)")
func hasLone(_ s: String) -> Bool { s.unicodeScalars.contains { $0.value == 0xFFFF } }
while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    // JSONSerialization replaces lone surrogates with U+FFFD; treat those as unsupported.
    let clean = line.replacingOccurrences(of: #"\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\u[dD][c-fC-F])|(?<![0-9a-fA-F]{2})\\u[dD][c-fC-F][0-9a-fA-F]{2}"#, with: #"\uFFFF"#, options: .regularExpression)
    guard let msg = try? JSONSerialization.jsonObject(with: Data(clean.utf8)) as? [Any],
          let cases = msg[1] as? [[String]] else { FileHandle.standardError.write("bad request\n".data(using: .utf8)!); exit(1) }
    var out = "\(msg[0]) "
    for c in cases {
        let f = c[0], a = c[1], r = c[2], p = c[3]
        if hasLone(a) || hasLone(r) || hasLone(p) { out += "40"; continue }
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
            guard var re = try? Regex(src) else { out += "04"; continue }
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
