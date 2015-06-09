
(define-syntax inc
  (syntax-rules ()
    ((_ e) (lambdaf@ () e))))

(define-syntax lambdaf@
  (syntax-rules ()
    ((_ () e) (lambda () e))))

(define-syntax lambdag@
  (syntax-rules (:)
    ((_ (c) e) (lambda (c) e))
    ((_ (c : S D Y N T) e)
     (lambda (c)
       (let ((S (c->S c)) (D (c->D c)) (Y (c->Y c)) (N (c->N c)) (T (c->T c)))
         e)))))

(define rhs
  (lambda (pr)
    (cdr pr)))

(define lhs
  (lambda (pr)
    (car pr)))

; The unique value for variables that have not yet been bound to a value
(define unbound (list 'unbound))

(define var
  (let ((counter -1))
    (lambda (scope)
      (set! counter (+ 1 counter))
      (vector unbound scope counter))))

(define var?
  (lambda (x)
    (vector? x)))

; Creates a new scope that is not scope-eq? to any other scope
(define new-scope
  (lambda ()
    (list 'scope)))

; Scope used when variable bindings should always be made in the substitution,
; as in var=? and reification.
(define nonlocal-scope
  (list 'non-local-scope))

(define scope-eq? eq?)

(define var-eq? eq?)

(define var-id
  (lambda (x)
    (vector-ref x 2)))

(define var-scope
  (lambda (x)
    (vector-ref x 1)))

(define var-val
  (lambda (x)
    (vector-ref x 0)))

(define set-var-val!
  (lambda (x v)
    (vector-set! x 0 v)))

(define subst
  (lambda (mapping scope)
    (cons mapping scope)))

(define subst-map
  (lambda (s)
    (car s)))

(define subst-scope
  (lambda (s)
    (cdr s)))

(define subst-length
  (lambda (s)
    (subst-map-length (subst-map s))))

(define subst-eq?
  (lambda (s1 s2)
    (and (scope-eq? (subst-scope s1) (subst-scope s2))
         (subst-map-eq? (subst-map s1) (subst-map s2)))))

(define subst-with-scope
  (lambda (s new-scope)
    (subst (subst-map s) new-scope)))

(define empty-subst (subst empty-subst-map 0))

(define empty-c `(,empty-subst  ; S - substitution
                  ()            ; D - disequality
                  ()            ; Y - symbolo
                  ()            ; N - numbero
                  ()            ; T - absento
                  ))

(define (make-walk my-subst-lookup)
  (define f
    (lambda (u S)
      (if (var? u)
        (if (eq? (var-val u) unbound)
          (cond
            ((my-subst-lookup u (subst-map S)) =>
                                               (lambda (pr) (f (rhs pr) S)))
            (else u))
          (f (var-val u) S))
        u)))
  f)

(define walk (make-walk subst-map-lookup))

(define (make-unify ext-s mywalk)
  (define occurs-check
    (lambda (x v s)
      (let ((v (mywalk v s)))
        (cond
          ((var? v) (var-eq? v x))
          ((pair? v)
           (or
             (occurs-check x (car v) s)
             (occurs-check x (cdr v) s)))
          (else #f)))))

  (define ext-s-check
    (lambda (x v s)
      (cond
        ((occurs-check x v s) #f)
        (else (ext-s s x v)))))

  (define (unify u v s)
    (let ((u (mywalk u s))
          (v (mywalk v s)))
      (cond
        ((eq? u v) s)
        ((var? u) (ext-s-check u v s))
        ((var? v) (ext-s-check v u s))
        ((and (pair? u) (pair? v))
         (let ((s (unify (car u) (car v) s)))
           (and s (unify (cdr u) (cdr v) s))))
        ((equal? u v) s)
        (else #f))))

  unify)

(define subst-add
  (lambda (S x v)
    (if (scope-eq? (var-scope x) (subst-scope S))
      (begin
        (set-var-val! x v)
        S)
      (subst (subst-map-add (subst-map S) x v) (subst-scope S)))))

(define unify (make-unify subst-add walk))


; Variant of unification used for simplifying disequality constraints.

(define alist-walk (make-walk assq))

(define alist-subst-map-add
  (lambda (S var val) (cons (cons var val) S)))

(define alist-subst-add
  (lambda (S x v)
    (subst (alist-subst-map-add (subst-map S) x v) (subst-scope S))))

(define alist-unify (make-unify alist-subst-add alist-walk))


(define empty-f (lambdaf@ () (mzero)))

(define unify*
  (lambda (S+ S)
    (unify (map lhs S+) (map rhs S+) S)))

(define-syntax case-inf
  (syntax-rules ()
    ((_ e (() e0) ((f^) e1) ((c^) e2) ((c f) e3))
     (let ((c-inf e))
       (cond
         ((not c-inf) e0)
         ((procedure? c-inf)  (let ((f^ c-inf)) e1))
         ((not (and (pair? c-inf)
                 (procedure? (cdr c-inf))))
          (let ((c^ c-inf)) e2))
         (else (let ((c (car c-inf)) (f (cdr c-inf)))
                 e3)))))))

(define-syntax fresh
  (syntax-rules ()
    ((_ (x ...) g0 g ...)
     (lambdag@ (c : S D Y N T)
       (inc
         (let ((x (var (subst-scope S))) ...)
           (bind* (g0 `(,S ,D ,Y ,N ,T)) g ...)))))))

(define-syntax bind*
  (syntax-rules ()
    ((_ e) e)
    ((_ e g0 g ...) (bind* (bind e g0) g ...))))

(define bind
  (lambda (c-inf g)
    (case-inf c-inf
      (() (mzero))
      ((f) (inc (bind (f) g)))
      ((c) (g c))
      ((c f) (mplus (g c) (lambdaf@ () (bind (f) g)))))))

(define-syntax run
  (syntax-rules ()
    ((_ n (q) g0 g ...)
     (take n
       (lambdaf@ ()
         ((fresh (q) g0 g ...
            (lambdag@ (c : S D Y N T)
              (begin
                (let ((S (subst-with-scope S nonlocal-scope)))
                  (let ((z ((reify q) `(,S ,D ,Y ,N ,T))))
                    (choice z empty-f))))))
          empty-c))))
    ((_ n (q0 q1 q ...) g0 g ...)
     (run n (x) (fresh (q0 q1 q ...) g0 g ... (== `(,q0 ,q1 ,q ...) x))))))

(define-syntax run*
  (syntax-rules ()
    ((_ (q0 q ...) g0 g ...) (run #f (q0 q ...) g0 g ...))))

(define take
  (lambda (n f)
    (cond
      ((and n (zero? n)) '())
      (else
       (case-inf (f)
         (() '())
         ((f) (take n f))
         ((c) (cons c '()))
         ((c f) (cons c
                  (take (and n (- n 1)) f))))))))

(define-syntax conde
  (syntax-rules ()
    ((_ (g0 g ...) (g1 g^ ...) ...)
     (lambdag@ (c : S D Y N T)
       (inc
         (let ((S (subst-with-scope S (new-scope))))
           (mplus*
             (bind* (g0 `(,S ,D ,Y ,N ,T)) g ...)
             (bind* (g1 `(,S ,D ,Y ,N ,T)) g^ ...) ...)))))))

(define-syntax mplus*
  (syntax-rules ()
    ((_ e) e)
    ((_ e0 e ...) (mplus e0
                    (lambdaf@ () (mplus* e ...))))))

(define mplus
  (lambda (c-inf f)
    (case-inf c-inf
      (() (f))
      ((f^) (inc (mplus (f) f^)))
      ((c) (choice c f))
      ((c f^) (choice c (lambdaf@ () (mplus (f) f^)))))))

(define c->S (lambda (c) (car c)))
(define c->D (lambda (c) (cadr c)))
(define c->Y (lambda (c) (caddr c)))
(define c->N (lambda (c) (cadddr c)))
(define c->T (lambda (c) (cadddr (cdr c))))

(define mzero (lambda () #f))

(define unit (lambda (c) c))

(define choice (lambda (c f) (cons c f)))

(define tagged?
  (lambda (S Y y^)
    (exists (lambda (y) (eqv? (walk y S) y^)) Y)))

(define untyped-var?
  (lambda (S Y N t^)
    (let ((in-type? (lambda (y) (var-eq? (walk y S) t^))))
      (and (var? t^)
           (not (exists in-type? Y))
           (not (exists in-type? N))))))

(define walk*
  (lambda (v S)
    (let ((v (walk v S)))
      (cond
        ((var? v) v)
        ((pair? v)
         (cons (walk* (car v) S) (walk* (cdr v) S)))
        (else v)))))

(define reify-S
  (lambda (v S)
    (let ((v (walk v S)))
      (cond
        ((var? v)
         (let ((n (subst-length S)))
           (let ((name (reify-name n)))
             (subst-add S v name))))
        ((pair? v)
         (let ((S (reify-S (car v) S)))
           (reify-S (cdr v) S)))
        (else S)))))

(define reify-name
  (lambda (n)
    (string->symbol
      (string-append "_" "." (number->string n)))))

(define drop-dot
  (lambda (X)
    (map (lambda (t)
           (let ((a (lhs t))
                 (d (rhs t)))
             `(,a ,d)))
         X)))

(define sorter
  (lambda (ls)
    (list-sort lex<=? ls)))

(define lex<=?
  (lambda (x y)
    (string<=? (datum->string x) (datum->string y))))

(define datum->string
  (lambda (x)
    (call-with-string-output-port
      (lambda (p) (display x p)))))

(define anyvar?
  (lambda (u r)
    (cond
      ((pair? u)
       (or (anyvar? (car u) r)
           (anyvar? (cdr u) r)))
      (else (var? (walk u r))))))

(define member*
  (lambda (u v)
    (cond
      ((equal? u v) #t)
      ((pair? v)
       (or (member* u (car v)) (member* u (cdr v))))
      (else #f))))

(define drop-N-b/c-const
  (lambdag@ (c : S D Y N T)
    (let ((const? (lambda (n)
                    (not (var? (walk n S))))))
      (cond
        ((find const? N) =>
         (lambda (n) `(,S ,D ,Y ,(remq1 n N) ,T)))
        (else c)))))

(define drop-Y-b/c-const
  (lambdag@ (c : S D Y N T)
    (let ((const? (lambda (y)
                    (not (var? (walk y S))))))
      (cond
	((find const? Y) =>
         (lambda (y) `(,S ,D ,(remq1 y Y) ,N ,T)))
        (else c)))))

(define remq1
  (lambda (elem ls)
    (cond
      ((null? ls) '())
      ((eq? (car ls) elem) (cdr ls))
      (else (cons (car ls) (remq1 elem (cdr ls)))))))

(define same-var?
  (lambda (v)
    (lambda (v^)
      (and (var? v) (var? v^) (var-eq? v v^)))))

(define find-dup
  (lambda (f S)
    (lambda (set)
      (let loop ((set^ set))
        (cond
          ((null? set^) #f)
          (else
           (let ((elem (car set^)))
             (let ((elem^ (walk elem S)))
               (cond
                 ((find (lambda (elem^^)
                          ((f elem^) (walk elem^^ S)))
                        (cdr set^))
                  elem)
                 (else (loop (cdr set^))))))))))))

(define drop-N-b/c-dup-var
  (lambdag@ (c : S D Y N T)
    (cond
      (((find-dup same-var? S) N) =>
       (lambda (n) `(,S ,D ,Y ,(remq1 n N) ,T)))
      (else c))))

(define drop-Y-b/c-dup-var
  (lambdag@ (c : S D Y N T)
    (cond
      (((find-dup same-var? S) Y) =>
       (lambda (y)
         `(,S ,D ,(remq1 y Y) ,N ,T)))
      (else c))))

(define var-type-mismatch?
  (lambda (S Y N t1^ t2^)
    (cond
      ((num? S N t1^) (not (num? S N t2^)))
      ((sym? S Y t1^) (not (sym? S Y t2^)))
      (else #f))))

(define term-ununifiable?
  (lambda (S Y N t1 t2)
    (let ((t1^ (walk t1 S))
          (t2^ (walk t2 S)))
      (cond
        ((or (untyped-var? S Y N t1^) (untyped-var? S Y N t2^)) #f)
        ((var? t1^) (var-type-mismatch? S Y N t1^ t2^))
        ((var? t2^) (var-type-mismatch? S Y N t2^ t1^))
        ((and (pair? t1^) (pair? t2^))
         (or (term-ununifiable? S Y N (car t1^) (car t2^))
             (term-ununifiable? S Y N (cdr t1^) (cdr t2^))))
        (else (not (eqv? t1^ t2^)))))))

(define T-term-ununifiable?
  (lambda (S Y N)
    (lambda (t1)
      (let ((t1^ (walk t1 S)))
        (letrec
            ((t2-check
              (lambda (t2)
                (let ((t2^ (walk t2 S)))
                  (cond
                    ((pair? t2^) (and
                                  (term-ununifiable? S Y N t1^ t2^)
                                  (t2-check (car t2^))
                                  (t2-check (cdr t2^))))
                    (else (term-ununifiable? S Y N t1^ t2^)))))))
          t2-check)))))

(define num?
  (lambda (S N n)
    (let ((n (walk n S)))
      (cond
        ((var? n) (tagged? S N n))
        (else (number? n))))))

(define sym?
  (lambda (S Y y)
    (let ((y (walk y S)))
      (cond
        ((var? y) (tagged? S Y y))
        (else (symbol? y))))))

(define drop-T-b/c-Y-and-N
  (lambdag@ (c : S D Y N T)
    (let ((drop-t? (T-term-ununifiable? S Y N)))
      (cond
        ((find (lambda (t) ((drop-t? (lhs t)) (rhs t))) T) =>
         (lambda (t) `(,S ,D ,Y ,N ,(remq1 t T))))
        (else c)))))

(define move-T-to-D-b/c-t2-atom
  (lambdag@ (c : S D Y N T)
    (cond
      ((exists (lambda (t)
               (let ((t2^ (walk (rhs t) S)))
                 (cond
                   ((and (not (untyped-var? S Y N t2^))
                         (not (pair? t2^)))
                    (let ((T (remq1 t T)))
                      `(,S ((,t) . ,D) ,Y ,N ,T)))
                   (else #f))))
             T))
      (else c))))

(define terms-pairwise=?
  (lambda (pr-a^ pr-d^ t-a^ t-d^ S)
    (or
     (and (term=? pr-a^ t-a^ S)
          (term=? pr-d^ t-a^ S))
     (and (term=? pr-a^ t-d^ S)
          (term=? pr-d^ t-a^ S)))))

(define T-superfluous-pr?
  (lambda (S Y N T)
    (lambda (pr)
      (let ((pr-a^ (walk (lhs pr) S))
            (pr-d^ (walk (rhs pr) S)))
        (cond
          ((exists
               (lambda (t)
                 (let ((t-a^ (walk (lhs t) S))
                       (t-d^ (walk (rhs t) S)))
                   (terms-pairwise=? pr-a^ pr-d^ t-a^ t-d^ S)))
             T)
           (for-all
            (lambda (t)
              (let ((t-a^ (walk (lhs t) S))
                    (t-d^ (walk (rhs t) S)))
                (or
                 (not (terms-pairwise=? pr-a^ pr-d^ t-a^ t-d^ S))
                 (untyped-var? S Y N t-d^)
                 (pair? t-d^))))
            T))
          (else #f))))))

(define drop-from-D-b/c-T
  (lambdag@ (c : S D Y N T)
    (cond
      ((find
           (lambda (d)
             (exists
                 (T-superfluous-pr? S Y N T)
               d))
         D) =>
         (lambda (d) `(,S ,(remq1 d D) ,Y ,N ,T)))
      (else c))))

(define drop-t-b/c-t2-occurs-t1
  (lambdag@ (c : S D Y N T)
    (cond
      ((find (lambda (t)
               (let ((t-a^ (walk (lhs t) S))
                     (t-d^ (walk (rhs t) S)))
                 (mem-check t-d^ t-a^ S)))
             T) =>
             (lambda (t)
               `(,S ,D ,Y ,N ,(remq1 t T))))
      (else c))))

(define split-t-move-to-d-b/c-pair
  (lambdag@ (c : S D Y N T)
    (cond
      ((exists
         (lambda (t)
           (let ((t2^ (walk (rhs t) S)))
             (cond
               ((pair? t2^) (let ((ta `(,(lhs t) . ,(car t2^)))
                                  (td `(,(lhs t) . ,(cdr t2^))))
                              (let ((T `(,ta ,td . ,(remq1 t T))))
                                `(,S ((,t) . ,D) ,Y ,N ,T))))
               (else #f))))
         T))
      (else c))))

(define find-d-conflict
  (lambda (S Y N)
    (lambda (D)
      (find
       (lambda (d)
	 (exists (lambda (pr)
		   (term-ununifiable? S Y N (lhs pr) (rhs pr)))
		 d))
       D))))

(define drop-D-b/c-Y-or-N
  (lambdag@ (c : S D Y N T)
    (cond
      (((find-d-conflict S Y N) D) =>
       (lambda (d) `(,S ,(remq1 d D) ,Y ,N ,T)))
      (else c))))

(define cycle
  (lambdag@ (c)
    (let loop ((c^ c)
               (fns^ (LOF))
               (n (length (LOF))))
      (cond
        ((zero? n) c^)
        ((null? fns^) (loop c^ (LOF) n))
        (else
         (let ((c^^ ((car fns^) c^)))
           (cond
             ((not (eq? c^^ c^))
              (loop c^^ (cdr fns^) (length (LOF))))
             (else (loop c^ (cdr fns^) (sub1 n))))))))))

(define absento
  (lambda (u v)
    (lambdag@ (c : S D Y N T)
      (cond
        [(mem-check u v S) (mzero)]
        [else (unit `(,S ,D ,Y ,N ((,u . ,v) . ,T)))]))))

(define mem-check
  (lambda (u t S)
    (let ((t (walk t S)))
      (cond
        ((pair? t)
         (or (term=? u t S)
             (mem-check u (car t) S)
             (mem-check u (cdr t) S)))
        (else (term=? u t S))))))

(define term=?
  (lambda (u t S)
    (cond
      ((unify u t (subst-with-scope S nonlocal-scope)) =>
       (lambda (S0)
         (subst-map-eq? (subst-map S0) (subst-map S))))
      (else #f))))

(define ground-non-<type>?
  (lambda (pred)
    (lambda (u S)
      (let ((u (walk u S)))
        (cond
          ((var? u) #f)
          (else (not (pred u))))))))

(define ground-non-symbol?
  (ground-non-<type>? symbol?))

(define ground-non-number?
  (ground-non-<type>? number?))

(define symbolo
  (lambda (u)
    (lambdag@ (c : S D Y N T)
      (cond
        [(ground-non-symbol? u S) (mzero)]
        [(mem-check u N S) (mzero)]
        [else (unit `(,S ,D (,u . ,Y) ,N ,T))]))))

(define numbero
  (lambda (u)
    (lambdag@ (c : S D Y N T)
      (cond
        [(ground-non-number? u S) (mzero)]
        [(mem-check u Y S) (mzero)]
        [else (unit `(,S ,D ,Y (,u . ,N) ,T))]))))

(define =/=
  (lambda (u v)
    (lambdag@ (c : S D Y N T)
      (cond
        ((unify u v (subst-with-scope S nonlocal-scope)) =>
         (lambda (S+)
           (if (subst-map-eq? (subst-map S+) (subst-map S))
             (mzero)
             (unit `(,S (((,u . ,v)) . ,D) ,Y ,N ,T)))))
        (else c)))))

(define ==
  (lambda (u v)
    (lambdag@ (c : S D Y N T)
      (cond
        ((unify u v S) =>
         (lambda (S0)
           (cond
             ((==fail-check S0 D Y N T) (mzero))
             (else (unit `(,S0 ,D ,Y ,N ,T))))))
        (else (mzero))))))

(define succeed (== #f #f))

(define fail (== #f #t))

(define ==fail-check
  (lambda (S0 D Y N T)
    (let ([S0 (subst-with-scope S0 nonlocal-scope)])
      (cond
        ((atomic-fail-check S0 Y ground-non-symbol?) #t)
        ((atomic-fail-check S0 N ground-non-number?) #t)
        ((symbolo-numbero-fail-check S0 Y N) #t)
        ((=/=-fail-check S0 D) #t)
        ((absento-fail-check S0 T) #t)
        (else #f)))))

(define atomic-fail-check
  (lambda (S A pred)
    (exists (lambda (a) (pred (walk a S) S)) A)))

(define symbolo-numbero-fail-check
  (lambda (S A N)
    (let ((N (map (lambda (n) (walk n S)) N)))
      (exists (lambda (a) (exists (same-var? (walk a S)) N))
        A))))

(define absento-fail-check
  (lambda (S T)
    (exists (lambda (t) (mem-check (lhs t) (rhs t) S)) T)))

(define =/=-fail-check
  (lambda (S D)
    (exists (d-fail-check S) D)))

(define d-fail-check
  (lambda (S)
    (lambda (d)
      (cond
        ((unify* d S) =>
           (lambda (S+) (subst-eq? S+ S)))
        (else #f)))))

(define reify
  (lambda (x)
    (lambda (c)
      (let ((c (cycle c)))
        (let* ((S (c->S c))
             (D (walk* (c->D c) S))
             (Y (walk* (c->Y c) S))
             (N (walk* (c->N c) S))
             (T (walk* (c->T c) S)))
        (let ((v (walk* x S)))
          (let ((R (reify-S v (subst empty-subst-map nonlocal-scope))))
            (reify+ v R
                    (let ((D (remp
                              (lambda (d)
                                (let ((dw (walk* d S)))
                                  (anyvar? dw R)))
                               (rem-xx-from-d c))))
                      (rem-subsumed D))
                    (remp
                     (lambda (y) (var? (walk y R)))
                     Y)
                    (remp
                     (lambda (n) (var? (walk n R)))
                     N)
                    (remp (lambda (t)
                            (anyvar? t R)) T)))))))))

(define reify+
  (lambda (v R D Y N T)
    (form (walk* v R)
          (walk* D R)
          (walk* Y R)
          (walk* N R)
          (rem-subsumed-T (walk* T R)))))

(define form
  (lambda (v D Y N T)
    (let ((fd (sort-D D))
          (fy (sorter Y))
          (fn (sorter N))
          (ft (sorter T)))
      (let ((fd (if (null? fd) fd
                    (let ((fd (drop-dot-D fd)))
                      `((=/= . ,fd)))))
            (fy (if (null? fy) fy `((sym . ,fy))))
            (fn (if (null? fn) fn `((num . ,fn))))
            (ft (if (null? ft) ft
                    (let ((ft (drop-dot ft)))
                      `((absento . ,ft))))))
        (cond
          ((and (null? fd) (null? fy)
                (null? fn) (null? ft))
           v)
          (else (append `(,v) fd fn fy ft)))))))

(define sort-D
  (lambda (D)
    (sorter
     (map sort-d D))))

(define sort-d
  (lambda (d)
    (list-sort
       (lambda (x y)
         (lex<=? (car x) (car y)))
       (map sort-pr d))))

(define drop-dot-D
  (lambda (D)
    (map drop-dot D)))

(define lex<-reified-name?
  (lambda (r)
    (char<?
     (string-ref
      (datum->string r) 0)
     #\_)))

(define sort-pr
  (lambda (pr)
    (let ((l (lhs pr))
          (r (rhs pr)))
      (cond
        ((lex<-reified-name? r) pr)
        ((lex<=? r l) `(,r . ,l))
        (else pr)))))

(define rem-subsumed
  (lambda (D)
    (let rem-subsumed ((D D) (d^* '()))
      (cond
        ((null? D) d^*)
        ((or (subsumed? (car D) (cdr D))
             (subsumed? (car D) d^*))
         (rem-subsumed (cdr D) d^*))
        (else (rem-subsumed (cdr D)
                (cons (car D) d^*)))))))

(define subsumed?
  (lambda (d d*)
    (cond
      ((null? d*) #f)
      (else
        (let* ((S (unify* d (subst empty-subst-map nonlocal-scope)))
               (S+ (unify* (car d*) S)))
          (or
            (and S+ (subst-eq? S+ S))
            (subsumed? d (cdr d*))))))))

(define alist-unify*
  (lambda (S+ S)
    (alist-unify (map lhs S+) (map rhs S+) S)))

(define rem-xx-from-d
  (lambdag@ (c : S D Y N T)
    (let ((D (walk* D S)))
      (remp not
            (map (lambda (d)
                   (cond
                     ((unify* d S) =>
                      (lambda (S0)
                        (cond
                          ((==fail-check S0 '() Y N T) #f)
                          (else (subst-map (alist-unify* d (subst '() nonlocal-scope)))))))
                     (else #f)))
                 D)))))

(define rem-subsumed-T
  (lambda (T)
    (let rem-subsumed ((T T) (T^ '()))
      (cond
        ((null? T) T^)
        (else
         (let ((lit (lhs (car T)))
               (big (rhs (car T))))
           (cond
             ((or (subsumed-T? lit big (cdr T))
                  (subsumed-T? lit big T^))
              (rem-subsumed (cdr T) T^))
             (else (rem-subsumed (cdr T)
                     (cons (car T) T^))))))))))

(define subsumed-T?
  (lambda (lit big T)
    (cond
      ((null? T) #f)
      (else
       (let ((lit^ (lhs (car T)))
             (big^ (rhs (car T))))
         (or
           (and (eq? big big^) (member* lit^ lit))
           (subsumed-T? lit big (cdr T))))))))

(define LOF
  (lambda ()
    `(,drop-N-b/c-const ,drop-Y-b/c-const ,drop-Y-b/c-dup-var
      ,drop-N-b/c-dup-var ,drop-D-b/c-Y-or-N ,drop-T-b/c-Y-and-N
      ,move-T-to-D-b/c-t2-atom ,split-t-move-to-d-b/c-pair
      ,drop-from-D-b/c-T ,drop-t-b/c-t2-occurs-t1)))
