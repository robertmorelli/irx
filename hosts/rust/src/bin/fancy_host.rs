//! fancy-regex host (backtracking with lookaround; delegates simple parts to `regex`).
fn main() {
    irx_hosts::serve("fancy-regex", |flags, a, r, pat, repeat| {
        let src = format!("{}\\A(?:{})\\z", irx_hosts::inline_flags(flags), pat);
        let re = match fancy_regex::Regex::new(&src) { Ok(re) => re, Err(_) => return 0x04 };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                match re.is_match(s) { Ok(true) => bits |= (1 << k) << (rep * 4), Ok(false) => {}, Err(_) => return 0x08 }
            }
        }
        bits
    });
}
