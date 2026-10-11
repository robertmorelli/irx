//! fancy-regex host (backtracking with lookaround; delegates simple parts to `regex`).
fn main() {
    irx_hosts::serve_all("fancy-regex", |flags, a, r, pat, repeat| {
        let src = format!("{}\\A(?:{})\\z", irx_hosts::inline_flags(flags), pat);
        let re = match fancy_regex::Regex::new(&src) { Ok(re) => re, Err(_) => return 0x04 };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                match re.is_match(s) { Ok(true) => bits |= (1 << k) << (rep * 4), Ok(false) => {}, Err(_) => return 0x08 }
            }
        }
        bits
    }, |flags, a, r, pat| {
        let src = format!("{}{}", irx_hosts::inline_flags(flags), pat);
        let re = fancy_regex::Regex::new(&src).map_err(|_| 0x04u8)?;
        let mut out = [None, None];
        for (k, s) in [a, r].iter().enumerate() {
            out[k] = re.find(s).map_err(|_| 0x08u8)?.map(|m| (m.start(), m.end()));
        }
        Ok(out)
    }, |flags, a, r, pat| {
        let src = format!("{}{}", irx_hosts::inline_flags(flags), pat);
        let re = fancy_regex::Regex::new(&src).map_err(|_| 0x04u8)?;
        let mut out = [[None; 7]; 2];
        for (k, s) in [a, r].iter().enumerate() {
            if let Some(c) = re.captures(s).map_err(|_| 0x08u8)? { for g in 0..7.min(c.len()) { out[k][g] = c.get(g).map(|m| (m.start(), m.end())); } }
        }
        Ok(out)
    });
}
