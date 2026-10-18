//! `regress` crate host (the ECMAScript regex engine behind Boa). Subjects are matched as UTF-16:
//! `find_from_utf16` under u/v and `find_from_ucs2` otherwise, as Boa does; spans are UTF-16
//! indices; subjects keep lone surrogates. Full match via the multiline-safe wrapper (?<![\s\S])(?:p)(?![\s\S]).
use regress::{Flags, Regex};

fn compile(flags: &str, pat: &str) -> Result<Regex, u8> {
    Regex::with_flags(pat, Flags::from(flags)).map_err(|_| 0x04u8)
}

fn unicode(flags: &str) -> bool {
    flags.contains('u') || flags.contains('v')
}

/// First match at or after `start` (UTF-16 index) in `s`.
fn first(re: &Regex, flags: &str, s: &[u16], start: usize) -> Option<regress::Match> {
    if start > s.len() { return None; }
    if unicode(flags) { re.find_from_utf16(s, start).next() } else { re.find_from_ucs2(s, start).next() }
}

fn main() {
    // Subjects come as raw UTF-16 (lone surrogates included), as a JS engine sees them.
    irx_hosts::allow_lone_surrogates();
    irx_hosts::serve_all("regress", |flags, _a, _r, pat, repeat| {
        let re = match compile(flags, &format!("(?<![\\s\\S])(?:{})(?![\\s\\S])", pat)) { Ok(re) => re, Err(e) => return e };
        let subj = [irx_hosts::raw(1), irx_hosts::raw(2)];
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in subj.iter().enumerate() {
                if first(&re, flags, s, 0).is_some() { bits |= (1 << k) << (rep * 4); }
            }
        }
        bits
    }, |flags, _a, _r, pat| {
        let re = compile(flags, pat)?;
        let subj = [irx_hosts::raw(1), irx_hosts::raw(2)];
        let mut out = [None; 2];
        for k in 0..2 {
            let st = irx_hosts::start(k);
            out[k] = first(&re, flags, &subj[k], st).filter(|m| !irx_hosts::sticky() || m.start() == st).map(|m| (m.start(), m.end()));
        }
        Ok(out)
    }, |flags, _a, _r, pat| {
        let re = compile(flags, pat)?;
        let subj = [irx_hosts::raw(1), irx_hosts::raw(2)];
        Ok([0, 1].map(|k| {
            let mut out = [None; 7];
            if let Some(m) = first(&re, flags, &subj[k], 0) {
                for (g, slot) in out.iter_mut().enumerate() {
                    *slot = m.group(g).map(|x| (x.start, x.end));
                }
            }
            out
        }))
    });
}
