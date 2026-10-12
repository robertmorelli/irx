//! irx line protocol for Rust regex hosts (same format as vendor/hosts/c/proto.h).
use std::io::{BufRead, Write};

fn hex4(b: &[u8]) -> Option<u32> {
    if b.len() < 4 { return None; }
    u32::from_str_radix(std::str::from_utf8(&b[..4]).ok()?, 16).ok()
}

/// Parse a JSON string at b[*i] == '"'. Returns (text, had_lone_surrogate).
fn parse_str(b: &[u8], i: &mut usize) -> Option<(String, bool)> {
    if b.get(*i) != Some(&b'"') { return None; }
    *i += 1;
    let mut s: Vec<u8> = Vec::new();
    let mut bad = false;
    let pushc = |s: &mut Vec<u8>, c: char| { let mut t = [0u8; 4]; s.extend_from_slice(c.encode_utf8(&mut t).as_bytes()); };
    while *i < b.len() && b[*i] != b'"' {
        if b[*i] != b'\\' { s.push(b[*i]); *i += 1; continue; }
        *i += 1;
        match b.get(*i)? {
            b'"' => s.push(b'"'), b'\\' => s.push(b'\\'), b'/' => s.push(b'/'),
            b'n' => s.push(b'\n'), b'r' => s.push(b'\r'), b't' => s.push(b'\t'),
            b'b' => s.push(8), b'f' => s.push(12),
            b'u' => {
                let c = hex4(&b[*i + 1..])?;
                *i += 4;
                if (0xD800..=0xDBFF).contains(&c) && b.get(*i + 1) == Some(&b'\\') && b.get(*i + 2) == Some(&b'u') {
                    if let Some(d) = hex4(&b[*i + 3..]) {
                        if (0xDC00..=0xDFFF).contains(&d) {
                            pushc(&mut s, char::from_u32(0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00))?);
                            *i += 6 + 1;
                            continue;
                        }
                    }
                }
                match char::from_u32(c) { Some(ch) => pushc(&mut s, ch), None => { bad = true; pushc(&mut s, '\u{FFFD}'); } }
            }
            _ => return None,
        }
        *i += 1;
    }
    if b.get(*i) != Some(&b'"') { return None; }
    *i += 1;
    Some((String::from_utf8(s).ok()?, bad))
}

/// First match of an unanchored search in A and R as byte ranges, or failure bits.
pub type SpanResult = Result<[Option<(usize, usize)>; 2], u8>;

/// Offset mode (ospan): where subject k's search starts (bytes); 0 in every other mode.
static START: [std::sync::atomic::AtomicUsize; 2] = [std::sync::atomic::AtomicUsize::new(0), std::sync::atomic::AtomicUsize::new(0)];
pub fn start(k: usize) -> usize {
    START[k].load(std::sync::atomic::Ordering::Relaxed)
}
/// Sticky mode (aspan): the match must start at start(k). Only hosts that check it enable it.
static STICKY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
pub fn sticky() -> bool {
    STICKY.load(std::sync::atomic::Ordering::Relaxed)
}

/// Run the protocol loop. `case(flags, a, r, pattern, repeat) -> bits`.
pub fn serve(name: &str, case: impl Fn(&str, &str, &str, &str, bool) -> u8) {
    serve_span(name, case, |_, _, _, _| Err(0x40));
}

/// Whole match then groups 1..6 per subject as byte ranges (None = no match / unset).
pub type CaptureResult = Result<[[Option<(usize, usize)>; 7]; 2], u8>;

/// Like `serve`, plus mode "span": `span(flags, a, r, pattern)` (see src/span.zig).
pub fn serve_span(name: &str, case: impl Fn(&str, &str, &str, &str, bool) -> u8, span: impl Fn(&str, &str, &str, &str) -> SpanResult) {
    serve_all(name, case, span, |_, _, _, _| Err(0x40));
}

/// Like `serve_span`, plus mode "capture" (see src/capture.zig).
pub fn serve_all(name: &str, case: impl Fn(&str, &str, &str, &str, bool) -> u8, span: impl Fn(&str, &str, &str, &str) -> SpanResult, capture: impl Fn(&str, &str, &str, &str) -> CaptureResult) {
    let mode = std::env::args().nth(1).unwrap_or_else(|| "default".into());
    let repeat = mode == "repeat" || mode == "tierup";
    // Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
    let wide = mode == "lspan" || mode == "lcapture";
    let pair = |s: usize, e: usize| if wide { format!("{:04x}{:04x}", s, e) } else { format!("{:02x}{:02x}", s, e) };
    let none = if wide { "ffffffff" } else { "ffff" };
    let failed = |e: u8, rest: usize| if wide { format!("fffe{:04x}{}", e, "0000".repeat(rest)) } else { format!("fe{:02x}{}", e, "00".repeat(rest)) };
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    writeln!(out, "ready {} mode={}", name, mode).unwrap();
    out.flush().unwrap();
    for line in std::io::stdin().lock().lines() {
        let line = line.unwrap();
        let b = line.as_bytes();
        let mut i = 1;
        let start = i;
        while i < b.len() && b[i].is_ascii_digit() { i += 1; }
        let seq = &line[start..i];
        let mut resp = format!("{} ", seq);
        i += 2; // ",["
        loop {
            while i < b.len() && b[i] == b',' { i += 1; }
            if i >= b.len() || b[i] == b']' { break; }
            i += 1; // '['
            let mut f = Vec::new();
            for k in 0..4 {
                let (s, bad) = parse_str(b, &mut i).expect("bad case");
                f.push((s, bad));
                if k < 3 { i += 1; }
            }
            i += 1; // ']'
            if mode == "capture" || mode == "lcapture" {
                if f.iter().any(|x| x.1) { resp.push_str(&failed(0x40, 26)); continue; }
                match capture(&f[0].0, &f[1].0, &f[2].0, &f[3].0) {
                    Err(e) => resp.push_str(&failed(e, 26)),
                    Ok(subj) => for gs in subj { for g in gs { match g { Some((s, e)) => resp.push_str(&pair(s, e)), None => resp.push_str(none) } } },
                }
                continue;
            }
            if mode == "span" || mode == "lspan" || mode == "ospan" || mode == "aspan" {
                STICKY.store(mode == "aspan", std::sync::atomic::Ordering::Relaxed);
                if f.iter().any(|x| x.1) { resp.push_str(&failed(0x40, 2)); continue; }
                // ospan: "<flags>@<a>,<r>" sets the search starts.
                let mut fl = f[0].0.clone();
                START[0].store(0, std::sync::atomic::Ordering::Relaxed);
                START[1].store(0, std::sync::atomic::Ordering::Relaxed);
                if let Some(at) = fl.find('@') {
                    let offs: Vec<usize> = fl[at + 1..].split(',').map(|x| x.parse().unwrap_or(0)).collect();
                    for (k, o) in offs.iter().take(2).enumerate() { START[k].store(*o, std::sync::atomic::Ordering::Relaxed); }
                    fl.truncate(at);
                }
                match span(&fl, &f[1].0, &f[2].0, &f[3].0) {
                    Err(e) => resp.push_str(&failed(e, 2)),
                    Ok(ms) => for m in ms { match m { Some((s, e)) => resp.push_str(&pair(s, e)), None => resp.push_str(none) } },
                }
                continue;
            }
            let bits = if f.iter().any(|x| x.1) { 0x40 } else { case(&f[0].0, &f[1].0, &f[2].0, &f[3].0, repeat) };
            resp.push_str(&format!("{:02x}", bits));
        }
        writeln!(out, "{}", resp).unwrap();
        out.flush().unwrap();
    }
}

pub fn inline_flags(flags: &str) -> String {
    let f: String = "ims".chars().filter(|c| flags.contains(*c)).collect();
    if f.is_empty() { String::new() } else { format!("(?{})", f) }
}
