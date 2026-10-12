// irx host: llvm::Regex (POSIX ERE, byte-oriented). Perl-dialect input is translated:
// (?: and (?<gN> -> (, \x{H} -> raw UTF-8, \d -> [0-9], \s -> [[:space:]], \w -> [[:alnum:]_].
// Lazy quantifiers, lookarounds and \b have no ERE form (translation error -> compile error bit).
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Regex.h"
#include <string>
#include "proto.h"
const char *host_name(void) { return "llvm-regex"; }
static bool translate(const std::string &s, std::string &o) {
    for (size_t i = 0; i < s.size(); i++) {
        char c = s[i];
        if (c == '\\') {
            char d = s[++i];
            if (d == 'x') { size_t e = s.find('}', i); uint32_t cp = std::stoul(s.substr(i + 2, e - i - 2), nullptr, 16); i = e;
                Str t = {0}; put_cp(&t, cp); std::string lit(t.buf, t.len); free(t.buf);
                if (lit.size() == 1 && strchr("^$.|?*+()[]{}\\", lit[0])) o += '\\'; o += lit; }
            else if (d == 'd') o += "[0-9]"; else if (d == 'D') o += "[^0-9]";
            else if (d == 's') o += "[[:space:]]"; else if (d == 'S') o += "[^[:space:]]";
            else if (d == 'w') o += "[[:alnum:]_]"; else if (d == 'W') o += "[^[:alnum:]_]";
            else if (d == 'b' || d == 'B') return false;
            else { o += '\\'; o += d; }
        } else if (c == '(' && s.compare(i, 3, "(?:") == 0) { o += '('; i += 2; }
        else if (c == '(' && s.compare(i, 3, "(?<") == 0 && i + 3 < s.size() && s[i + 3] == 'g') { size_t e = s.find('>', i); o += '('; i = e; }
        else if (c == '(' && i + 1 < s.size() && s[i + 1] == '?') return false;
        else if ((c == '*' || c == '+' || c == '?' || c == '}') && i + 1 < s.size() && s[i + 1] == '?') return false;
        else if (c == '[') {
            o += '['; i++;
            if (s[i] == '^') { o += '^'; i++; }
            std::string items, tail;
            while (s[i] != ']') {
                if (s[i] == '\\') { char d = s[++i];
                    if (d == 'x') { size_t e = s.find('}', i); uint32_t cp = std::stoul(s.substr(i + 2, e - i - 2), nullptr, 16); i = e; Str t = {0}; put_cp(&t, cp); items.append(t.buf, t.len); free(t.buf); }
                    else if (d == ']') o += ']';  // must come first
                    else if (d == '-') tail += '-';
                    else if (d == 'd') items += "0-9"; else if (d == 's') items += "[:space:]"; else if (d == 'w') items += "[:alnum:]_";
                    else items += d;
                } else items += s[i];
                i++;
            }
            o += items + tail + ']';
        } else o += c;
    }
    return true;
}
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    std::string ere;
    if (!translate(std::string(pat, plen), ere)) return 0x04;
    llvm::Regex::RegexFlags f = llvm::Regex::NoFlags;
    if (strchr(flags, 'i')) f = (llvm::Regex::RegexFlags)(f | llvm::Regex::IgnoreCase);
    if (strchr(flags, 'm')) f = (llvm::Regex::RegexFlags)(f | llvm::Regex::Newline);
    // Under REG_NEWLINE ^/$ are line anchors, so the wrapper can't force a full match there;
    // instead match unanchored and require the (leftmost-longest) match to span the subject.
    bool m = strchr(flags, 'm') != nullptr;
    std::string full = m ? "(" + ere + ")" : "^(" + ere + ")$";
    llvm::Regex re(llvm::StringRef(full), f);
    std::string err;
    if (!re.isValid(err)) return 0x04;
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
        for (int k = 0; k < 2; k++)
        {
            llvm::SmallVector<llvm::StringRef, 2> ms;
            llvm::StringRef sr(subj[k], lens[k]);
            bool hit = m ? (re.match(sr, &ms) && ms[0].data() == sr.data() && ms[0].size() == sr.size()) : re.match(sr);
            if (hit) bits |= (1 << k) << (rep * 4);
        }
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    if (host_anchored) return 0x40;
    if (host_start[0] || host_start[1]) return 0x40; /* no start-offset search */
    std::string ere;
    if (!translate(std::string(pat, plen), ere)) return 0x04;
    llvm::Regex::RegexFlags f = llvm::Regex::NoFlags;
    if (strchr(flags, 'i')) f = (llvm::Regex::RegexFlags)(f | llvm::Regex::IgnoreCase);
    if (strchr(flags, 'm')) f = (llvm::Regex::RegexFlags)(f | llvm::Regex::Newline);
    llvm::Regex re(llvm::StringRef("(" + ere + ")"), f);
    std::string err;
    if (!re.isValid(err)) return 0x04;
    for (int k = 0; k < 2; k++) {
        llvm::SmallVector<llvm::StringRef, 2> ms;
        llvm::StringRef sr(subj[k], lens[k]);
        if (re.match(sr, &ms)) { out[2 * k] = ms[0].data() - sr.data(); out[2 * k + 1] = out[2 * k] + (long)ms[0].size(); }
        else out[2 * k] = out[2 * k + 1] = -1;
    }
    return 0;
}
/* Capture mode is not modelled for this engine: unsupported. */
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    (void)flags; (void)subj; (void)lens; (void)pat; (void)plen; (void)out;
    return 0x40;
}
