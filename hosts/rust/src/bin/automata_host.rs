//! regex-automata host: one of the crate's engines, chosen by IRX_RA_ENGINE: pikevm (default),
//! backtrack (bounded backtracker), onepass, hybrid (lazy DFA), dfa (dense DFA). The `regex` crate
//! picks among these internally; here each is driven directly. A pattern the engine cannot run
//! (not one-pass, Unicode word boundary in a DFA, size limits) is unsupported (0x40); a pattern
//! the `regex` crate rejects is a compile error (0x04).
use regex_automata::{dfa, hybrid, nfa::thompson::{backtrack::BoundedBacktracker, pikevm::PikeVM}, util::syntax, Anchored, Input};

fn engine() -> String { std::env::var("IRX_RA_ENGINE").unwrap_or_else(|_| "pikevm".into()) }

fn cfg(flags: &str) -> syntax::Config {
    syntax::Config::new().case_insensitive(flags.contains('i')).multi_line(flags.contains('m')).dot_matches_new_line(flags.contains('s'))
}

/// Leftmost-first search: Ok(Some((start, end))), Ok(None), or failure bits.
type Find = Box<dyn FnMut(&Input) -> Result<Option<(usize, usize)>, u8>>;
/// Captures (whole match + groups 1..6), or failure bits.
type Caps = Box<dyn FnMut(&Input) -> Result<[Option<(usize, usize)>; 7], u8>>;

fn build(flags: &str, pat: &str, want_caps: bool) -> Result<(Find, Option<Caps>), u8> {
    if regex_automata::util::syntax::parse(pat).is_err() { return Err(0x04); }  // syntax only: no size limit
    let c = cfg(flags);
    match engine().as_str() {
        "backtrack" => {
            let re = BoundedBacktracker::builder().syntax(c).build(pat).map_err(|_| 0x40u8)?;
            let re2 = re.clone();
            let mut cache = re.create_cache();
            let mut cache2 = re.create_cache();
            let find: Find = Box::new(move |i| re.try_find(&mut cache, i.clone()).map(|m| m.map(|m| (m.start(), m.end()))).map_err(|_| 0x40));
            let caps: Caps = Box::new(move |i| {
                let mut cs = re2.create_captures();
                re2.try_search(&mut cache2, i, &mut cs).map_err(|_| 0x40u8)?;
                Ok(std::array::from_fn(|g| cs.get_group(g).map(|s| (s.start, s.end))))
            });
            Ok((find, if want_caps { Some(caps) } else { None }))
        }
        "onepass" => {
            let re = dfa::onepass::DFA::builder().syntax(c).build(pat).map_err(|_| 0x40u8)?;
            let re2 = re.clone();
            let mut cache = re.create_cache();
            let mut cache2 = re.create_cache();
            // One-pass DFAs only run anchored searches: a search from k is an anchored search at
            // each start in turn (leftmost first), which is what an unanchored search would find.
            let find: Find = Box::new(move |i| {
                let mut cs = re.create_captures();
                let anchored_only = matches!(i.get_anchored(), Anchored::Yes);
                for at in i.start()..=i.end() {
                    let inp = i.clone().range(at..).anchored(Anchored::Yes);
                    re.try_search(&mut cache, &inp, &mut cs).map_err(|_| 0x40u8)?;
                    if let Some(m) = cs.get_match() { return Ok(Some((m.start(), m.end()))); }
                    if anchored_only { break; }
                }
                Ok(None)
            });
            let caps: Caps = Box::new(move |i| {
                let mut cs = re2.create_captures();
                for at in i.start()..=i.end() {
                    let inp = i.clone().range(at..).anchored(Anchored::Yes);
                    re2.try_search(&mut cache2, &inp, &mut cs).map_err(|_| 0x40u8)?;
                    if cs.is_match() { break; }
                }
                Ok(std::array::from_fn(|g| cs.get_group(g).map(|s| (s.start, s.end))))
            });
            Ok((find, if want_caps { Some(caps) } else { None }))
        }
        "hybrid" => {
            if want_caps { return Err(0x40); }
            let re = hybrid::regex::Regex::builder().syntax(c).build(pat).map_err(|_| 0x40u8)?;
            let mut cache = re.create_cache();
            Ok((Box::new(move |i| re.try_search(&mut cache, i).map(|m| m.map(|m| (m.start(), m.end()))).map_err(|_| 0x40)), None))
        }
        "dfa" => {
            if want_caps { return Err(0x40); }
            let re = dfa::regex::Regex::builder().syntax(c)
                .dense(dfa::dense::Config::new().dfa_size_limit(Some(4 << 20)).determinize_size_limit(Some(4 << 20)))
                .build(pat).map_err(|_| 0x40u8)?;
            Ok((Box::new(move |i| re.try_search(i).map(|m| m.map(|m| (m.start(), m.end()))).map_err(|_| 0x40)), None))
        }
        _ => {
            let re = PikeVM::builder().syntax(c).build(pat).map_err(|_| 0x40u8)?;
            let re2 = re.clone();
            let mut cache = re.create_cache();
            let mut cache2 = re.create_cache();
            let find: Find = Box::new(move |i| Ok(re.find(&mut cache, i.clone()).map(|m| (m.start(), m.end()))));
            let caps: Caps = Box::new(move |i| {
                let mut cs = re2.create_captures();
                re2.search(&mut cache2, i, &mut cs);
                Ok(std::array::from_fn(|g| cs.get_group(g).map(|s| (s.start, s.end))))
            });
            Ok((find, if want_caps { Some(caps) } else { None }))
        }
    }
}

fn main() {
    irx_hosts::bench(|flags, pat| {
        let (mut find, _) = build(flags, pat, false)?;
        Ok(Box::new(move |s: &str| find(&Input::new(s)).map(|m| m.is_some()).map_err(|_| ())))
    });
    // Global search through the crate's own iterator (it skips an empty match where the last
    // match ended).
    irx_hosts::global(|flags, s, pat| {
        let (mut find, _) = build(flags, pat, false)?;
        let mut err = None;
        let mut it = regex_automata::util::iter::Searcher::new(Input::new(s));
        let mut out = Vec::new();
        while out.len() < 4 {
            let r = it.try_advance(|inp| match find(inp) {
                Ok(m) => Ok(m.map(|(a, b)| regex_automata::Match::must(0, a..b))),
                Err(e) => { err = Some(e); Err(regex_automata::MatchError::gave_up(inp.start())) }
            });
            match r { Ok(Some(m)) => out.push((m.start(), m.end())), Ok(None) => break, Err(_) => return Err(err.unwrap_or(0x40)) }
        }
        Ok(out)
    });
    let name = format!("regex-automata-{}", engine());
    irx_hosts::serve_all(&name, |flags, a, r, pat, repeat| {
        let (mut find, _) = match build(flags, &format!("\\A(?:{})\\z", pat), false) { Ok(x) => x, Err(e) => return e };
        let mut bits = 0u8;
        for rep in 0..if repeat { 2 } else { 1 } {
            for (k, s) in [a, r].iter().enumerate() {
                match find(&Input::new(s)) { Ok(Some(_)) => bits |= (1 << k) << (rep * 4), Ok(None) => {}, Err(e) => return e }
            }
        }
        bits
    }, |flags, a, r, pat| {
        let (mut find, _) = build(flags, pat, false)?;
        let sticky = irx_hosts::sticky();
        let mut out = [None, None];
        for (k, s) in [a, r].iter().enumerate() {
            let mut inp = Input::new(*s).range(irx_hosts::start(k)..);
            if sticky { inp = inp.anchored(Anchored::Yes); }
            out[k] = find(&inp)?;
        }
        Ok(out)
    }, |flags, a, r, pat| {
        let (_, caps) = build(flags, pat, true)?;
        let mut caps = caps.ok_or(0x40u8)?;
        Ok([caps(&Input::new(a))?, caps(&Input::new(r))?])
    });
}
