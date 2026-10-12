/* PCRE1 host (8.45, Homebrew pcre; deprecated upstream but still embedded widely). UTF-8 + UCP, full
 * match via \A(?:p)\z; IRX_PCRE1_JIT=1 studies each pattern with PCRE_STUDY_JIT_COMPILE. */
#include <pcre.h>
#include "proto.h"
const char *host_name(void) { static char o[64]; snprintf(o, sizeof o, "pcre1-%s%s", pcre_version(), getenv("IRX_PCRE1_JIT") ? "-jit" : ""); return o; }
static pcre *compile(const char *flags, const char *src, pcre_extra **extra) {
    int opt = PCRE_UTF8 | PCRE_UCP | PCRE_NO_UTF8_CHECK;
    if (strchr(flags, 'i')) opt |= PCRE_CASELESS;
    if (strchr(flags, 'm')) opt |= PCRE_MULTILINE;
    if (strchr(flags, 's')) opt |= PCRE_DOTALL;
    const char *err; int eoff;
    pcre *re = pcre_compile(src, opt, &err, &eoff, NULL);
    *extra = NULL;
    if (re && getenv("IRX_PCRE1_JIT")) *extra = pcre_study(re, PCRE_STUDY_JIT_COMPILE, &err);
    return re;
}
static void release(pcre *re, pcre_extra *extra) { if (extra) pcre_free_study(extra); pcre_free(re); }
/* PCRE_ERROR_MATCHLIMIT / RECURSIONLIMIT / JIT_STACKLIMIT are resource limits (unsupported). */
static int failbits(int rc) { return rc == PCRE_ERROR_MATCHLIMIT || rc == PCRE_ERROR_RECURSIONLIMIT || rc == PCRE_ERROR_JIT_STACKLIMIT ? 0x40 : 0x08; }
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    Str w = {0}; put(&w, "\\A(?:", 5); put(&w, pat, plen); put(&w, ")\\z", 3);
    pcre_extra *x; pcre *re = compile(flags, w.buf, &x); free(w.buf);
    if (!re) return 0x04;
    int bits = 0, ov[30];
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
        for (int k = 0; k < 2; k++) {
            int rc = pcre_exec(re, x, subj[k], (int)lens[k], 0, 0, ov, 30);
            if (rc >= 0) bits |= (1 << k) << (rep * 4);
            else if (rc != PCRE_ERROR_NOMATCH) { bits = failbits(rc); goto done; }
        }
done:
    release(re, x);
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    Str w = {0}; put(&w, pat, plen); put(&w, "", 0);
    pcre_extra *x; pcre *re = compile(flags, w.buf, &x); free(w.buf);
    if (!re) return 0x04;
    int e = 0, ov[30];
    for (int k = 0; k < 2; k++) {
        int rc = pcre_exec(re, x, subj[k], (int)lens[k], (int)host_start[k], host_anchored ? PCRE_ANCHORED : 0, ov, 30);
        if (rc >= 0) { out[2 * k] = ov[0]; out[2 * k + 1] = ov[1]; }
        else if (rc == PCRE_ERROR_NOMATCH) out[2 * k] = out[2 * k + 1] = -1;
        else { e = failbits(rc); break; }
    }
    release(re, x);
    return e;
}
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    Str w = {0}; put(&w, pat, plen); put(&w, "", 0);
    pcre_extra *x; pcre *re = compile(flags, w.buf, &x); free(w.buf);
    if (!re) return 0x04;
    int e = 0, ov[3 * CAP_PAIRS];
    for (int k = 0; k < 2; k++) {
        int rc = pcre_exec(re, x, subj[k], (int)lens[k], 0, 0, ov, 3 * CAP_PAIRS);
        if (rc < 0 && rc != PCRE_ERROR_NOMATCH) { e = failbits(rc); break; }
        for (int g = 0; g < CAP_PAIRS; g++) {
            int set = rc >= 0 && (rc == 0 || g < rc) && ov[2 * g] >= 0;
            out[k][2 * g] = set ? ov[2 * g] : -1; out[k][2 * g + 1] = set ? ov[2 * g + 1] : -1;
        }
    }
    release(re, x);
    return e;
}
