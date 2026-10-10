/* PCRE2 host: Perl-like semantics, UTF + UCP, full match via \A(?:p)\z. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include "proto.h"
const char *host_name(void) { static char b[64]; pcre2_config(PCRE2_CONFIG_VERSION, b); static char o[96]; snprintf(o, sizeof o, "pcre2-%s%s", b, getenv("IRX_PCRE2_JIT") ? "-jit" : ""); return o; }
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    uint32_t opt = PCRE2_UTF | PCRE2_UCP;
    if (strchr(flags, 'i')) opt |= PCRE2_CASELESS;
    if (strchr(flags, 'm')) opt |= PCRE2_MULTILINE;
    if (strchr(flags, 's')) opt |= PCRE2_DOTALL;
    Str w = {0}; put(&w, "\\A(?:", 5); put(&w, pat, plen); put(&w, ")\\z", 3);
    int err; PCRE2_SIZE off;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)w.buf, w.len, opt, &err, &off, NULL);
    free(w.buf);
    if (!re) return 0x04;
    if (getenv("IRX_PCRE2_JIT")) pcre2_jit_compile(re, PCRE2_JIT_COMPLETE);
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
        for (int k = 0; k < 2; k++) {
            int rc = pcre2_match(re, (PCRE2_SPTR)subj[k], lens[k], 0, 0, md, NULL);
            if (rc >= 0) bits |= (1 << k) << (rep * 4);
            else if (rc != PCRE2_ERROR_NOMATCH) { bits = 0x08; goto done; }
        }
done:
    pcre2_match_data_free(md); pcre2_code_free(re);
    return bits;
}
