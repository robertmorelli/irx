/* irx host: Vectorscan/Hyperscan block mode, UTF8 + UCP. Full match via \A(?:p)\z. */
#include <hs/hs.h>
#include "proto.h"
const char *host_name(void) { static char b[64]; snprintf(b, sizeof b, "vectorscan-%s", hs_version()); return b; }
static int on_match(unsigned id, unsigned long long from, unsigned long long to, unsigned flags, void *ctx) { *(int *)ctx = 1; return 1; }
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    unsigned f = HS_FLAG_UTF8 | HS_FLAG_UCP | HS_FLAG_SINGLEMATCH | HS_FLAG_ALLOWEMPTY;
    if (strchr(flags, 'i')) f |= HS_FLAG_CASELESS;
    if (strchr(flags, 'm')) f |= HS_FLAG_MULTILINE;
    if (strchr(flags, 's')) f |= HS_FLAG_DOTALL;
    Str w = {0}; put(&w, "\\A(?:", 5); put(&w, pat, plen); put(&w, ")\\z", 3);
    hs_database_t *db; hs_compile_error_t *err;
    int rc = hs_compile(w.buf, f, HS_MODE_BLOCK, NULL, &db, &err);
    free(w.buf);
    if (rc != HS_SUCCESS) {
        if (getenv("IRX_DEBUG")) fprintf(stderr, "%.*s: %s\n", (int)plen, pat, err->message);
        /* "Pattern is too large" is a resource limit, not a syntax error: unsupported. */
        int too_large = strstr(err->message, "too large") != NULL;
        hs_free_compile_error(err);
        return too_large ? 0x40 : 0x04;
    }
    hs_scratch_t *scr = NULL;
    if (hs_alloc_scratch(db, &scr) != HS_SUCCESS) { hs_free_database(db); return 0x08; }
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
        for (int k = 0; k < 2; k++) {
            int hit = 0;
            hs_error_t e = hs_scan(db, subj[k], (unsigned)lens[k], 0, scr, on_match, &hit);
            if (e != HS_SUCCESS && e != HS_SCAN_TERMINATED) { bits = 0x08; goto done; }
            if (hit) bits |= (1 << k) << (rep * 4);
        }
done:
    hs_free_scratch(scr); hs_free_database(db);
    return bits;
}
/* Span mode is not modelled for Vectorscan (it reports match ends only): unsupported. */
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    if (host_anchored) return 0x40;
    (void)flags; (void)subj; (void)lens; (void)pat; (void)plen; (void)out;
    return 0x40;
}
/* Capture mode is not modelled for this engine: unsupported. */
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    (void)flags; (void)subj; (void)lens; (void)pat; (void)plen; (void)out;
    return 0x40;
}
