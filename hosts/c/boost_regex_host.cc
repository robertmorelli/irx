// irx host: Boost.Regex (boost::wregex, Perl syntax) over code points (wchar_t is 32-bit here). Boost's
// defaults differ from Perl's, so every flag is explicit: m -> ^/$ at lines (else no_mod_m), s -> mod_s
// (else no_mod_s). Full match via regex_match.
#include <boost/regex.hpp>
#include <string>
#include "proto.h"
const char *host_name(void) { return "boost-regex"; }
static std::wstring widen(const char *s, size_t n) {  // UTF-8 -> code points
    std::wstring w;
    for (size_t i = 0; i < n;) {
        unsigned char c = (unsigned char)s[i];
        uint32_t cp; int len;
        if (c < 0x80) { cp = c; len = 1; } else if (c < 0xE0) { cp = c & 0x1F; len = 2; } else if (c < 0xF0) { cp = c & 0x0F; len = 3; } else { cp = c & 0x07; len = 4; }
        for (int k = 1; k < len && i + k < n; k++) cp = (cp << 6) | ((unsigned char)s[i + k] & 0x3F);
        w.push_back((wchar_t)cp); i += len;
    }
    return w;
}
static boost::regex::flag_type opts(const char *flags) {
    unsigned o = boost::regex::perl;
    if (strchr(flags, 'i')) o |= boost::regex::icase;
    if (!strchr(flags, 'm')) o |= boost::regex::no_mod_m;
    o |= strchr(flags, 's') ? boost::regex::mod_s : boost::regex::no_mod_s;
    return (boost::regex::flag_type)o;
}
/* Code-point index -> UTF-8 byte offset in s (the target reports utf8 units). */
static long byteOff(const char *s, size_t n, long cps) {
    size_t i = 0; long k = 0;
    while (i < n && k < cps) { unsigned char c = (unsigned char)s[i]; i += c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4; k++; }
    return (long)i;
}
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    boost::wregex re;
    try { re.assign(widen(pat, plen), opts(flags)); } catch (const std::runtime_error &) { return 0x04; }
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    try {
        for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
            for (int k = 0; k < 2; k++)
                if (boost::regex_match(widen(subj[k], lens[k]), re)) bits |= (1 << k) << (rep * 4);
    } catch (const std::runtime_error &) { return 0x40; }  // error_complexity / error_stack: resource limits
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    if (host_anchored || host_start[0] || host_start[1]) return 0x40;
    boost::wregex re;
    try { re.assign(widen(pat, plen), opts(flags)); } catch (const std::runtime_error &) { return 0x04; }
    try {
        for (int k = 0; k < 2; k++) {
            std::wstring w = widen(subj[k], lens[k]);
            boost::wsmatch m;
            if (boost::regex_search(w, m, re)) { out[2 * k] = byteOff(subj[k], lens[k], m.position((std::size_t)0)); out[2 * k + 1] = byteOff(subj[k], lens[k], m.position((std::size_t)0) + m.length((std::size_t)0)); }
            else out[2 * k] = out[2 * k + 1] = -1;
        }
    } catch (const std::runtime_error &) { return 0x40; }
    return 0;
}
/* Capture mode is not modelled for this engine yet: unsupported. */
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    (void)flags; (void)subj; (void)lens; (void)pat; (void)plen; (void)out;
    return 0x40;
}
