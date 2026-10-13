//! fancy-regex host (backtracking with lookaround; delegates simple parts to `regex`).
/// Runtime errors: exceeding the backtrack limit is a resource limit, reported as unsupported
/// (0x40); anything else is an exception (0x08).
fn err_bits(e: fancy_regex::Error) -> u8 {
    match e {
        fancy_regex::Error::RuntimeError(fancy_regex::RuntimeError::BacktrackLimitExceeded) => 0x40,
        _ => 0x08,
    }
}

fn main() {
    irx_hosts::bench(|flags, pat| {
        let re = fancy_regex::RegexBuilder::new(&format!("{}{}", irx_hosts::inline_flags(flags), pat)).delegate_size_limit(64 << 20).build().map_err(|_| 0x04u8)?;
        Ok(Box::new(move |s: &str| re.is_match(s).map_err(|_| ())))
    });
    irx_hosts::global(|flags, s, pat| {
        let re = fancy_regex::RegexBuilder::new(&format!("{}{}", irx_hosts::inline_flags(flags), pat)).delegate_size_limit(64 << 20).build().map_err(|_| 0x04u8)?;
        re.find_iter(s).take(4).map(|m| m.map(|m| (m.start(), m.end())).map_err(err_bits)).collect()
    });
    irx_hosts::serve_all("fancy-regex", |flags, a, r, pat, repeat| {
        let src = format!("{}\\A(?:{})\\z", irx_hosts::inline_flags(flags), pat);
        let re = match fancy_regex::RegexBuilder::new(&src).delegate_size_limit(64 << 20).build() { Ok(re) => re, Err(_) => return 0x04 };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                match re.is_match(s) { Ok(true) => bits |= (1 << k) << (rep * 4), Ok(false) => {}, Err(e) => return err_bits(e) }
            }
        }
        bits
    }, |flags, a, r, pat| {
        let src = format!("{}{}", irx_hosts::inline_flags(flags), pat);
        let re = fancy_regex::RegexBuilder::new(&src).delegate_size_limit(64 << 20).build().map_err(|_| 0x04u8)?;
        let mut out = [None, None];
        for (k, s) in [a, r].iter().enumerate() {
            out[k] = re.find_from_pos(s, irx_hosts::start(k)).map_err(err_bits)?.filter(|m| !irx_hosts::sticky() || m.start() == irx_hosts::start(k)).map(|m| (m.start(), m.end()));
        }
        Ok(out)
    }, |flags, a, r, pat| {
        let src = format!("{}{}", irx_hosts::inline_flags(flags), pat);
        let re = fancy_regex::RegexBuilder::new(&src).delegate_size_limit(64 << 20).build().map_err(|_| 0x04u8)?;
        let mut out = [[None; 7]; 2];
        for (k, s) in [a, r].iter().enumerate() {
            if let Some(c) = re.captures(s).map_err(err_bits)? { for g in 0..7.min(c.len()) { out[k][g] = c.get(g).map(|m| (m.start(), m.end())); } }
        }
        Ok(out)
    });
}
