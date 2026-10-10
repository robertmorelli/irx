//! RE# (`resharp` crate) host: derivative-based engine over UTF-8 bytes. Full match via \A(?:p)\z.
fn main() {
    irx_hosts::serve("resharp", |flags, a, r, pat, repeat| {
        let src = format!("{}\\A(?:{})\\z", irx_hosts::inline_flags(flags), pat);
        let re = match resharp::Regex::new(&src) { Ok(re) => re, Err(_) => return 0x04 };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                match re.is_match(s.as_bytes()) { Ok(true) => bits |= (1 << k) << (rep * 4), Ok(false) => {}, Err(_) => return 0x08 }
            }
        }
        bits
    });
}
