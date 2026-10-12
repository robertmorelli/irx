#lang racket/base
;; irx host: Racket #px regexps. Perl-dialect input: \x{H} -> raw char, (?<gN> -> (.
(require json racket/string racket/port)
(define args (current-command-line-arguments))
(define mode (if (> (vector-length args) 0) (vector-ref args 0) "default"))
(define rep (if (member mode '("repeat" "tierup")) 2 1))
(printf "ready racket-~a mode=~a\n" (version) mode) (flush-output)
;; Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
(define wide (and (member mode '("lspan" "lcapture")) #t))
(define is-span (and (member mode '("span" "lspan" "ospan")) #t))
(define is-cap (and (member mode '("capture" "lcapture")) #t))
(define D (if wide 4 2))
(define (hx n) (let ([h (number->string n 16)]) (string-append (make-string (max 0 (- D (string-length h))) #\0) h)))
(define NONE (make-string (* 2 D) #\f))
(define (failed b rest) (string-append (if wide "fffe" "fe") (hx b) (make-string (* D rest) #\0)))
(define (fix p)
  (let* ([p (regexp-replace* #px"\\\\x\\{([0-9A-Fa-f]+)\\}" p
                             (lambda (_ h) (let ([c (integer->char (string->number h 16))])
                                             (if (regexp-match? #px"[\\\\^$.|?*+()\\[\\]{}]" (string c)) (string #\\ c) (string c)))))]
         [p (regexp-replace* #px"\\(\\?<g[0-9]+>" p "(")])
    p))
(define lone-rx #px"\\\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\\\u[dD][c-fC-F])|(?<![0-9a-fA-F]{2})\\\\u[dD][c-fC-F][0-9a-fA-F]{2}")
(for ([line (in-lines)])
  (unless (string=? (string-trim line) "")
    (define msg (string->jsexpr (regexp-replace* lone-rx line "\\\\uFFFF")))
    (define out (open-output-string))
    (fprintf out "~a " (car msg))
    (for ([c (cadr msg)])
      (define f0 (car c)) (define a (cadr c)) (define r (caddr c)) (define p (cadddr c))
      ;; ospan: "<flags>@<a>,<r>" = search start per subject (characters)
      (define at (let loop ([i 0]) (cond [(>= i (string-length f0)) #f] [(char=? (string-ref f0 i) #\@) i] [else (loop (add1 i))])))
      (define f (if at (substring f0 0 at) f0))
      (define starts (if at (map string->number (string-split (substring f0 (add1 at)) ",")) '(0 0)))
      (cond
        [(for/or ([s (list a r p)]) (string-contains? s "￿")) (write-string (cond [is-span (failed #x40 2)] [is-cap (failed #x40 26)] [else "40"]) out)]
        [is-cap
         ;; Whole match + groups 1..6 per subject, character offsets (src/capture.zig).
         (define modes (string-append (if (string-contains? f "i") "i" "") (if (string-contains? f "s") "s" "") (if (string-contains? f "m") "m" "")))
         (define src (if (string=? modes "") (fix p) (string-append "(?" modes ":" (fix p) ")")))
         (define rx (with-handlers ([exn:fail? (lambda (e) #f)]) (pregexp src)))
         (write-string
          (cond
            [(not rx) (failed 4 26)]
            [else
             (with-handlers ([exn:fail? (lambda (e) (failed 8 26))])
               (apply string-append
                      (for*/list ([s (list a r)] [m (in-value (regexp-match-positions rx s))] [g 7])
                        (define x (and m (< g (length m)) (list-ref m g)))
                        (if x (string-append (hx (car x)) (hx (cdr x))) NONE))))])
          out)]
        [is-span
         ;; Unanchored search, character offsets (src/span.zig).
         (define modes (string-append (if (string-contains? f "i") "i" "") (if (string-contains? f "s") "s" "") (if (string-contains? f "m") "m" "")))
         (define src (if (string=? modes "") (fix p) (string-append "(?" modes ":" (fix p) ")")))
         (define rx (with-handlers ([exn:fail? (lambda (e) #f)]) (pregexp src)))
         (write-string
          (cond
            [(not rx) (failed 4 2)]
            [else
             (with-handlers ([exn:fail? (lambda (e) (failed 8 2))])
               (apply string-append
                      (for/list ([s (list a r)] [st starts])
                        ;; The text before the start is the input prefix (lookbehind, ^).
                        (define m (regexp-match-positions rx s st #f #f (string->bytes/utf-8 (substring s 0 st))))
                        (if m (string-append (hx (caar m)) (hx (cdar m))) NONE))))])
          out)]
        [else
         (define modes (string-append (if (string-contains? f "i") "i" "") (if (string-contains? f "s") "s" "") (if (string-contains? f "m") "m" "")))
         (define src (string-append "^(?:" (if (string=? modes "") "" (string-append "(?" modes ":")) (fix p) (if (string=? modes "") "" ")") ")$"))
         (define rx (with-handlers ([exn:fail? (lambda (e) #f)]) (pregexp src)))
         (cond
           [(not rx) (write-string "04" out)]
           [else
            (define bits
              (with-handlers ([exn:fail? (lambda (e) 8)])
                (for*/fold ([b 0]) ([k rep] [j 2])
                  (if (regexp-match? rx (if (= j 0) a r)) (bitwise-ior b (arithmetic-shift (arithmetic-shift 1 j) (* 4 k))) b))))
            (write-string (string-append (if (< bits 16) "0" "") (number->string bits 16)) out)])]))
    (write-string (get-output-string out)) (newline) (flush-output)))
