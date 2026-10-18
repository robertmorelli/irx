/* PCRE2 host: Perl-like semantics, UTF + UCP, full match via \A(?:p)\z. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include "proto.h"

/* A match that hit PCRE2's resource limits (match, depth, heap or JIT stack) is reported as a
 * limit (0x40, skipped by irx), not as an exception (0x08). */
static int err_bits(int rc) {
    switch (rc) {
    case PCRE2_ERROR_MATCHLIMIT:
    case PCRE2_ERROR_DEPTHLIMIT:
    case PCRE2_ERROR_HEAPLIMIT:
    case PCRE2_ERROR_JIT_STACKLIMIT:
        return 0x40;
    default:
        return 0x08;
    }
}
const char *host_name(void) { static char b[64]; pcre2_config(PCRE2_CONFIG_VERSION, b); static char o[96]; snprintf(o, sizeof o, "pcre2-%s%s%s", b, getenv("IRX_PCRE2_JIT") ? "-jit" : "", getenv("IRX_PCRE2_NOUCP") ? "-noucp" : ""); return o; }
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    uint32_t opt = PCRE2_UTF | (getenv("IRX_PCRE2_NOUCP") ? 0 : PCRE2_UCP);
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
            else if (rc != PCRE2_ERROR_NOMATCH) { bits = err_bits(rc); goto done; }
        }
done:
    pcre2_match_data_free(md); pcre2_code_free(re);
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    uint32_t opt = PCRE2_UTF | (getenv("IRX_PCRE2_NOUCP") ? 0 : PCRE2_UCP);
    if (strchr(flags, 'i')) opt |= PCRE2_CASELESS;
    if (strchr(flags, 'm')) opt |= PCRE2_MULTILINE;
    if (strchr(flags, 's')) opt |= PCRE2_DOTALL;
    int err; PCRE2_SIZE off;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pat, plen, opt, &err, &off, NULL);
    if (!re) return 0x04;
    if (getenv("IRX_PCRE2_JIT")) pcre2_jit_compile(re, PCRE2_JIT_COMPLETE);
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    int e = 0;
    for (int k = 0; k < 2; k++) {
        int rc = pcre2_match(re, (PCRE2_SPTR)subj[k], lens[k], host_start[k], host_anchored ? PCRE2_ANCHORED : 0, md, NULL);
        if (rc >= 0) { PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md); out[2 * k] = (long)ov[0]; out[2 * k + 1] = (long)ov[1]; }
        else if (rc == PCRE2_ERROR_NOMATCH) out[2 * k] = out[2 * k + 1] = -1;
        else { e = err_bits(rc); break; }
    }
    pcre2_match_data_free(md); pcre2_code_free(re);
    return e;
}
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    uint32_t opt = PCRE2_UTF | (getenv("IRX_PCRE2_NOUCP") ? 0 : PCRE2_UCP);
    if (strchr(flags, 'i')) opt |= PCRE2_CASELESS;
    if (strchr(flags, 'm')) opt |= PCRE2_MULTILINE;
    if (strchr(flags, 's')) opt |= PCRE2_DOTALL;
    int err; PCRE2_SIZE off;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pat, plen, opt, &err, &off, NULL);
    if (!re) return 0x04;
    if (getenv("IRX_PCRE2_JIT")) pcre2_jit_compile(re, PCRE2_JIT_COMPLETE);
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    int e = 0;
    for (int k = 0; k < 2 && !e; k++) {
        for (int g = 0; g < 2 * CAP_PAIRS; g++) out[k][g] = -1;
        int rc = pcre2_match(re, (PCRE2_SPTR)subj[k], lens[k], 0, 0, md, NULL);
        if (rc >= 0) {
            PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md); uint32_t n = pcre2_get_ovector_count(md);
            for (uint32_t g = 0; g < n && g < CAP_PAIRS; g++)
                if (ov[2 * g] != PCRE2_UNSET) { out[k][2 * g] = (long)ov[2 * g]; out[k][2 * g + 1] = (long)ov[2 * g + 1]; }
        } else if (rc != PCRE2_ERROR_NOMATCH) e = err_bits(rc);
    }
    pcre2_match_data_free(md); pcre2_code_free(re);
    return e;
}

/* bench (Shootout 2): compile once, unanchored searches. */
typedef struct { pcre2_code *re; pcre2_match_data *md; } PB;
void *host_bench_compile(const char *flags, const char *pat, size_t plen) {
    uint32_t opt = PCRE2_UTF | (getenv("IRX_PCRE2_NOUCP") ? 0 : PCRE2_UCP);
    if (strchr(flags, 'i')) opt |= PCRE2_CASELESS;
    if (strchr(flags, 'm')) opt |= PCRE2_MULTILINE;
    if (strchr(flags, 's')) opt |= PCRE2_DOTALL;
    int err; PCRE2_SIZE off;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pat, plen, opt, &err, &off, NULL);
    if (!re) return NULL;
    if (getenv("IRX_PCRE2_JIT")) pcre2_jit_compile(re, PCRE2_JIT_COMPLETE);
    PB *b = (PB *)malloc(sizeof *b); b->re = re; b->md = pcre2_match_data_create_from_pattern(re, NULL);
    return b;
}
int host_bench_search(void *h, int k, const char *s, size_t len) {
    /* The warm-up search validates the UTF-8; timed searches skip the check, as callers that
     * validate once do (PHP, for one). */
    static const char *seen[2]; static size_t seenlen[2];
    PB *b = (PB *)h;
    uint32_t opt = (seen[k] == s && seenlen[k] == len) ? PCRE2_NO_UTF_CHECK : 0;
    seen[k] = s; seenlen[k] = len;
    int rc = pcre2_match(b->re, (PCRE2_SPTR)s, len, 0, opt, b->md, NULL);
    return rc >= 0 ? 1 : rc == PCRE2_ERROR_NOMATCH ? 0 : -1;
}
void host_bench_free(void *h) { PB *b = (PB *)h; pcre2_match_data_free(b->md); pcre2_code_free(b->re); free(b); }
