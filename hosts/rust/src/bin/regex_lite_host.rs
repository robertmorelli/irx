//! Rust `regex-lite` crate host (linear time, basic Unicode: ASCII classes and case folding). Full match via \A(?:p)\z.
fn main() {
    irx_hosts::serve_all("regex-lite", |flags, a, r, pat, repeat| {
        let src = format!("{}\\A(?:{})\\z", irx_hosts::inline_flags(flags), pat);
        let re = match regex_lite::RegexBuilder::new(&src).size_limit(64 << 20).build() { Ok(re) => re, Err(_) => return 0x04 };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                if re.is_match(s) { bits |= (1 << k) << (rep * 4); }
            }
        }
        bits
    }, |flags, a, r, pat| {
        let src = format!("{}{}", irx_hosts::inline_flags(flags), pat);
        let re = regex_lite::RegexBuilder::new(&src).size_limit(64 << 20).build().map_err(|_| 0x04u8)?;
        let (s0, s1) = (irx_hosts::start(0), irx_hosts::start(1));
        Ok([(a, s0), (r, s1)].map(|(s, k)| re.find_at(s, k).map(|m| (m.start(), m.end()))))
    }, |flags, a, r, pat| {
        let src = format!("{}{}", irx_hosts::inline_flags(flags), pat);
        let re = regex_lite::RegexBuilder::new(&src).size_limit(64 << 20).build().map_err(|_| 0x04u8)?;
        Ok([a, r].map(|s| {
            let mut out = [None; 7];
            if let Some(c) = re.captures(s) { for g in 0..7.min(c.len()) { out[g] = c.get(g).map(|m| (m.start(), m.end())); } }
            out
        }))
    });
}
