//! Rust `regex` crate host (linear time, Unicode by default). Full match via \A(?:p)\z.
fn main() {
    irx_hosts::serve("rust-regex", |flags, a, r, pat, repeat| {
        let src = format!("{}\\A(?:{})\\z", irx_hosts::inline_flags(flags), pat);
        let re = match regex::RegexBuilder::new(&src).size_limit(64 << 20).build() { Ok(re) => re, Err(_) => return 0x04 };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                if re.is_match(s) { bits |= (1 << k) << (rep * 4); }
            }
        }
        bits
    });
}
