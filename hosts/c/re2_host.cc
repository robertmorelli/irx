// RE2 host: linear-time, no lookaround/backrefs. Full match via \A(?:p)\z with inline flags.
#include <re2/re2.h>
#include "proto.h"
const char *host_name(void) { return "re2"; }
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    std::string w = "(?";
    if (strchr(flags, 'i')) w += 'i';
    if (strchr(flags, 'm')) w += 'm';
    if (strchr(flags, 's')) w += 's';
    w = (w == "(?") ? std::string() : w + ")";
    w += "\\A(?:" + std::string(pat, plen) + ")\\z";
    RE2::Options o; o.set_log_errors(false); o.set_max_mem(64 << 20);
    RE2 re(w, o);
    if (!re.ok()) return 0x04;
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
        for (int k = 0; k < 2; k++)
            if (RE2::PartialMatch(absl::string_view(subj[k], lens[k]), re)) bits |= (1 << k) << (rep * 4);
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    std::string w = "(?";
    if (strchr(flags, 'i')) w += 'i';
    if (strchr(flags, 'm')) w += 'm';
    if (strchr(flags, 's')) w += 's';
    w = (w == "(?") ? std::string() : w + ")";
    w += std::string(pat, plen);
    RE2::Options o; o.set_log_errors(false); o.set_max_mem(64 << 20);
    RE2 re(w, o);
    if (!re.ok()) return 0x04;
    for (int k = 0; k < 2; k++) {
        absl::string_view text(subj[k], lens[k]), m;
        if (re.Match(text, 0, text.size(), RE2::UNANCHORED, &m, 1)) { out[2 * k] = m.data() - text.data(); out[2 * k + 1] = out[2 * k] + (long)m.size(); }
        else out[2 * k] = out[2 * k + 1] = -1;
    }
    return 0;
}
