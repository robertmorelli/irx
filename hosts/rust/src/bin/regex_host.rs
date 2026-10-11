//! Rust `regex` crate host (linear time, Unicode by default). Full match via \A(?:p)\z.
fn main() {
    irx_hosts::serve_span("rust-regex", |flags, a, r, pat, repeat| {
        let src = format!("{}\\A(?:{})\\z", irx_hosts::inline_flags(flags), pat);
        let re = match regex::RegexBuilder::new(&src).size_limit(64 << 20).build() { Ok(re) => re, Err(_) => return 0x04 };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                if re.is_match(s) { bits |= (1 << k) << (rep * 4); }
            }
        }
        bits
    }, |flags, a, r, pat| {
        let src = format!("{}{}", irx_hosts::inline_flags(flags), pat);
        let re = regex::RegexBuilder::new(&src).size_limit(64 << 20).build().map_err(|_| 0x04u8)?;
        Ok([a, r].map(|s| re.find(s).map(|m| (m.start(), m.end()))))
    });
}
