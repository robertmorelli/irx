#lang racket/base
;; irx host: Racket #px regexps. Perl-dialect input: \x{H} -> raw char, (?<gN> -> (.
(require json racket/string racket/port)
(define args (current-command-line-arguments))
(define mode (if (> (vector-length args) 0) (vector-ref args 0) "default"))
(define rep (if (member mode '("repeat" "tierup")) 2 1))
(printf "ready racket-~a mode=~a\n" (version) mode) (flush-output)
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
      (define f (car c)) (define a (cadr c)) (define r (caddr c)) (define p (cadddr c))
      (cond
        [(for/or ([s (list a r p)]) (string-contains? s "￿")) (write-string (if (string=? mode "span") "fe400000" "40") out)]
        [(string=? mode "span")
         ;; Unanchored search, character offsets (src/span.zig).
         (define modes (string-append (if (string-contains? f "i") "i" "") (if (string-contains? f "s") "s" "") (if (string-contains? f "m") "m" "")))
         (define src (if (string=? modes "") (fix p) (string-append "(?" modes ":" (fix p) ")")))
         (define rx (with-handlers ([exn:fail? (lambda (e) #f)]) (pregexp src)))
         (define (hx n) (string-append (if (< n 16) "0" "") (number->string n 16)))
         (write-string
          (cond
            [(not rx) "fe040000"]
            [else
             (with-handlers ([exn:fail? (lambda (e) "fe080000")])
               (apply string-append
                      (for/list ([s (list a r)])
                        (define m (regexp-match-positions rx s))
                        (if m (string-append (hx (caar m)) (hx (cdar m))) "ffff"))))])
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
