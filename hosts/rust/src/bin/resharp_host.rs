//! RE# (`resharp` crate) host: derivative-based engine over UTF-8 bytes. Full match via \A(?:p)\z.
//! UnicodeMode::Full (`.` and negated classes step by code point, Unicode \w\d\s) and
//! multiline off, so ^/$ follow the irx m flag like the other engines.
fn main() {
    irx_hosts::serve_span("resharp", |flags, a, r, pat, repeat| {
        let src = format!("{}\\A(?:{})\\z", irx_hosts::inline_flags(flags), pat);
        let re = match resharp::Regex::with_options(&src, resharp::RegexOptions::default().unicode(resharp::UnicodeMode::Full).multiline(false)) { Ok(re) => re, Err(e) => { if std::env::var_os("IRX_DEBUG").is_some() { eprintln!("{src}: {e}"); } return 0x04 } };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                match re.is_match(s.as_bytes()) { Ok(true) => bits |= (1 << k) << (rep * 4), Ok(false) => {}, Err(_) => return 0x08 }
            }
        }
        bits
    }, |flags, a, r, pat| {
        // find_all yields leftmost-longest, non-overlapping matches; the first is the span.
        let src = format!("{}{}", irx_hosts::inline_flags(flags), pat);
        let re = resharp::Regex::with_options(&src, resharp::RegexOptions::default().unicode(resharp::UnicodeMode::Full).multiline(false)).map_err(|_| 0x04u8)?;
        let mut out = [None, None];
        for (k, s) in [a, r].iter().enumerate() {
            out[k] = re.find_all(s.as_bytes()).map_err(|_| 0x08u8)?.first().map(|m| (m.start, m.end));
        }
        Ok(out)
    });
}
