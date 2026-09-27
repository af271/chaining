;; UNION-GUIDED proof search.  The focused rule base is the union of ECAN's
;; top-N (by STI + normalised LTI) and WILLIAM's top-N (by predicted
;; probability that the rule appears in a proof of THIS goal).  Both keep the
;; fraction they use alone, so the union is at most twice as large and the
;; overlap is measured rather than assumed.
;;
;; All ECAN dynamics still run -- seeding, stimulation, Hebbian links,
;; diffusion and rent -- because ECAN's half of the union depends on them.

;; Experiment to verify or rediscover proofs of the propositional
;; calculus fragment of set theory of Metamath.
;;
;; This variant DOES use the stock metta-attention agents.  
;; Attention values live in the real bank (setAv / getSti / getLti /
;; stimulate) and &af is populated, so getAfAtoms yields a live bounded focus
;; and the diffusion and rent agents have targets to select.  What is still
;; local: Hebbian link maintenance and the &pc-rb-af rule focus.
;;
;; NOTE: every call into the bank goes through ecan-key, which prefixes the
;; label into a single SYMBOL ("L-" ++ LABEL).  Two things force that: the
;; bank stores untagged pairs, so a label colliding with a PeTTa builtin (the
;; corpus label `id') would reduce the pair away and setAv would silently
;; fail; and an Expression key would be mistaken for a link by the diffusion
;; agent.  See ecan-key.
;;
;; NOTE: rediscover-proofs-ecan makes two obc searches per evaluation
;; (focused then, on a miss, full).  Each is wrapped in `collapse` so a
;; miss becomes a value () rather than a hard Prolog failure that would
;; short-circuit the evaluation.  

;; NEXT: automate the discovery process of reduction rules.  It is
;; especially relevant here because new lemmas are constantly added.
;; Thus hand written reduction rules will not suffice.

;; Note that all type definitions over functions have been commented
;; out because it results in a significant speed up.

;;;;;;;;;;;;;;;;;;;;;;
;; ;;;;;;;;;;;;;;;; ;;
;; ;; Parameters ;; ;;
;; ;;;;;;;;;;;;;;;; ;;
;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Experiment Parameters ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Process assertions up to the provided index (excluded).  The
;; maximum value is 1526 because the full corpus contains 1525
;; assertions.  Set to 182 because the 182nd theorem is very slow to
;; prove.
(= (up-to-idx) 183)

;;;;;;;;;;;;;;;;;;;;;;;
;; Search Parameters ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; Whether to reverse the order of arguments.  For instance
;;
;; (: ax-mp (-> $𝜑 (→ $𝜑 $𝜓) $𝜓))
;;
;; becomes
;;
;; (: ax-mp (-> (→ $𝜑 $𝜓) $𝜑 $𝜓))
;;
;; This can speed up the proof search because in the reversed order,
;; the first arguments tend to be more constrained than the lastest
;; ones, which can have the effect of pruning earlier the search.
;;
;; Indeed, early results confirm that.  Reversing the arguments allows
;; to rediscover the first proofs (up to index 50 excluded) in 9.144s,
;; instead of 6m47.418s if not reversed.
(= (reverse-arguments) True)

;; For each theorem, search for all possible proofs.  Otherwise, stop
;; at the first one.
(= (search-all-proofs) False)

;; Shared wall-clock budget for the focused and full-KB tiers of one theorem.
;; The full tier receives only the time left after the focused tier finishes.
(= (theorem-timeout-seconds) 60)

;; Premise selector used to build the focused rule base.  Supported values:
;; ecan, william, union.  Every mode receives exactly (ecan-focus-size) slots.
(= (selector-mode) union)

;;;;;;;;;;;;;;;;;;;;;
;; ECAN Parameters ;;
;;;;;;;;;;;;;;;;;;;;;

;; Initial short-term importance (STI) assigned to an axiom label when
;; it is first inserted into the knowledge base.
(= (ecan-axiom-sti) 100.0)

;; Initial STI assigned to a (rule/arrow) lemma label on insertion.
;; Used as a FLOOR only -- see ecan-seed-sti below.
(= (ecan-rule-sti) 100.0)

;; Extra STI given to a freshly proved lemma on top of the current
;; maximum, so it enters the attentional focus at the very top.
;;
;; Why: the corpus is ordered so that a theorem is usually proved from
;; the lemmas just before it, making the newest lemma the single most
;; likely thing the next proof needs.  With a fixed seed the opposite
;; happened -- established rules accumulated STI in the 400-500 range
;; while every new lemma entered at 100, so it could not break into the
;; top-N focus. Seeding by recency puts the new lemma in the focus 
;; while it is most relevant; rent then decays it if it goes unused.
(= (ecan-seed-bonus) 1.0)

;; STI increment applied to every label used in a discovered proof.
(= (ecan-proof-stimulus) 1.0)

;; MASTER SWITCH.
;;
;;   True  -- ECAN-guided run: attention values are maintained, the focused
;;            rule base is rebuilt before every theorem, and the search is
;;            two-tier (focus first, full rule base on a miss).
;;   False -- plain run, behaviourally the base experiment
;;            ../../metamath/pc-xp.metta: no attention values, no focus, no
;;            agents, no Hebbian links, and a single search against the full
;;            rule base.  Use this as the control when measuring what ECAN buys.
;;
;; Everything ECAN-specific is gated on this in one of five places:
;; add-to-kbs (seeding), process-theorem-search (stimulation + Hebbian links),
;; rediscover-proofs-ecan (the focus and the second tier), ecan-run-agents
;; (diffusion + rent), and the daemon start/stop at the bottom of the file.
;;
;; NOTE every disabled branch must yield a VALUE, normally ().  Returning
;; (empty) instead propagates out through process-assertion and silently ends
;; the until loop -- which is exactly what this parameter used to do.
(= (ecan-use-agents) True)

;; Run the ECAN agents CONTINUOUSLY, on a background thread, for the whole
;; run -- instead of once between theorems.  hyperpose is PeTTa's concurrency
;; primitive (it compiles to concurrent_and), so the daemon and the proof
;; search are genuinely parallel SWI threads; metta-attention guards its
;; agents with with_mutex already.
;;
;; This is closer to the OpenCog design, where ECAN agents are MindAgents on
;; their own cycle rather than functions someone calls.  It also changes what
;; rent means: AFRentCollectionAgent bills elapsed wall clock above a
;; threshold of 1/AFRentFrequency seconds, which is a design for a free-running
;; agent.  Called once per theorem it produces spikes (one slow theorem was
;; billed 4871 STI); ticked steadily it produces the smooth decay it was
;; written for.
(= (ecan-background) True)

;; Seconds the daemon sleeps between sweeps.  MUST be >= 1/AFRentFrequency
;; (0.2 s at the stock value of 5.0) or every sweep falls under
;; collectAFRent's elapsed-time threshold and rent never collects at all.
(= (ecan-daemon-interval) 0.25)

;; Whether the daemon also rebuilds &pc-rb-af.  With this False the running
;; search keeps the focus it started with and only the NEXT theorem sees the
;; daemon's work.  With it True the rule base is mutated underneath an
;; in-flight search: each node's match sees a consistent snapshot, but
;; different nodes can see different ones, so tier-1 completeness is no longer
;; guaranteed.  That is survivable here only because a tier-1 miss falls
;; through to the full rule base -- it costs time, never correctness.
(= (ecan-daemon-steers-search) False)

;; Size of the attention-focused rule base (&pc-rb-af) as a FRACTION of
;; the rules currently in &pc-rb -- the analogue of AF_SIZE (0.2) in
;; AttentionParam.metta.  A fixed count does not work over a long run:
;; the rule base grows (51 rules at iteration 63, 135 by 181) while a
;; fixed focus stays put, so its coverage -- and with it the hit rate --
;; decays (measured at focus=20: 92% hits while full was 21-43, falling
;; to 16-28% once full passed 100).  A fraction holds coverage constant.
(= (ecan-focus-fraction) 0.3)

;; Lower bound on the focus.  Keep this at least at the previously
;; validated fixed size (20): a proof typically needs BOTH the freshly
;; proved lemma and an older workhorse rule, so too small a focus drops
;; one of them.  Measured at iteration 63 (syl3c, needs mpd + sylc): with
;; 12 slots the fresh sylc made it in but mpd was evicted -> miss -> 20
;; minute fallback.  The focused search itself is cheap (2.1% of total
;; runtime across a full run), so erring large is nearly free insurance.
(= (ecan-focus-min) 25)

;; Number of highest-STI inference rules kept in the focus: the fraction
;; of the current rule count, never below (ecan-focus-min).  Truncated to
;; an integer -- take-n counts down to 0, and a fractional bound would
;; never terminate exactly.  Set the fraction >= 1.0 to disable focusing
;; (focus == full base).
(= (ecan-focus-size)
   (let $n (size-atom (collapse (match &pc-rb (: $l $t) $l)))
     (max (ecan-focus-min)
          (trunc-math (* (ecan-focus-fraction) $n)))))

;; Log per-iteration tier diagnostics (focused size / full size / whether
;; the focused search hit) so the value of ECAN guidance can be measured.
(= (ecan-log-tier) True)

;; Weight of (normalised) LTI relative to STI when ranking rules for the
;; focus.  At 1.0 the most-used rule in the corpus gets an LTI bonus of
;; (ecan-sti-ceiling) points, so the focus becomes roughly "the most
;; recently proved lemmas" + "the most reliably useful rules" -- which is
;; exactly the pair a proof typically needs.  Set to 0.0 to rank by pure
;; STI (the previous, measurably worse, behaviour).  NOTE the two terms
;; are only at parity while the ceiling tracks the actual STI maximum;
;; see ecan-sti-ceiling.
;;
;; Why an LTI term is needed at all: STI alone measures RECENCY, and
;; recency churns.  Measured at iteration 63: `mpd` is used in 14 of the
;; first 63 proofs (most recently in iteration 62, immediately prior) and
;; STILL could not hold a top-20 STI slot -- so syl3c, whose proof is
;; (mpd (sylc ...) ...), missed the focused search and fell back to a
;; 20-minute full-KB search.  LTI is credited by the bank's own stimulate
;; (calculateLTIWage) and is never spent or renormalised, so it records
;; long-run usefulness independently of short-term STI churn.
(= (ecan-lti-weight) 1.0)

;; Blend rate pulling a Hebbian link's strength toward fresh co-use
;; evidence (TC_DECAY_RATE in AttentionParam.metta):
;; mean' = decay*1.0 + (1-decay)*mean on every co-occurrence.
(= (ecan-hebbian-decay) 0.1)

;; Nominal top of the STI range.  Its ONLY use is as the scale of the LTI
;; term in ecan-rule-score: the most-used rule in the corpus receives an LTI
;; bonus of exactly this many points, so the value sets how a perfect
;; long-run record trades off against raw STI (see ecan-lti-weight).  Keep it
;; near the STI maximum the economy actually settles at, or the two terms
;; stop being commensurate and the ranking collapses into one of them.
;;
;; This used to ALSO be a hard ceiling, enforced by rescaling the whole STI
;; vector once per iteration.  That is no longer needed: rent plus the
;; funds-driven wage taper bound STI on their own.  MEASURED over a full run
;; to 182 -- max STI rises to 880.4 around two thirds in and settles at
;; 761.7, and the rescale branch was taken exactly 0 times out of 176
;; iterations.  The rescaling code was therefore removed as dead weight.
;;
;; NOTE: nothing derives or enforces this number -- it is a hand-picked
;; constant, and since the rescaling went away nothing pins the actual STI
;; maximum to it either.  At 1000.0 against a measured maximum of ~762 the
;; LTI term is about 31% larger than parity with STI, so the focus leans
;; slightly further toward proven workhorses than ecan-lti-weight's comment
;; describes.  Setting it to ~800 would restore parity.
(= (ecan-sti-ceiling) 1000.0)

;;;;;;;;;;;;;;;;;;;;;;;
;; Logger Parameters ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; Log level
(= (log-level) debug)

;; Log file path.  Distinct from pc-xp-ECAN.metta's pc-xp.log: both files
;; sit in this directory and the logger appends rather than truncates, so
;; sharing a name would interleave the two experiments in one file.
(= (log-filepath) "pc-xp-union.log")

;;;;;;;;;;;;;;;;;;;
;; ;;;;;;;;;;;;; ;;
;; ;; Imports ;; ;;
;; ;;;;;;;;;;;;; ;;
;;;;;;;;;;;;;;;;;;;

;; Import logger library.  git-import! fetches the logger repo into
;; repos/ next to this file (idempotent if already present); then import
; the Prolog predicates directly from the cloned file.  Two notes:
;   1. git-import!'s base directory and import_prolog_functions_from_file's
;      path are both resolved against the cwd run.sh was invoked from, not
;      against this file, hence the working_dir anchoring and the two-arg
;      (library petta_lib_logger lib_logger.pl).
;   2. (library lib_logger) does NOT work here -- one-arg library resolves
;      against PeTTa's own lib/, where lib_logger.metta does not exist, and
;      import! swallows the failure silently, leaving the logger functions
;      unregistered and no log file written.
!(import! &self (library lib_import))
!(progn (translatePredicate (working_dir $this-dir))
        (translatePredicate (atomic_list_concat ($this-dir "/repos") $repos-dir))
        (git-import! "https://github.com/ngeiswei/petta_lib_logger" "" $repos-dir))
!(progn (translatePredicate (working_dir $bg-dir))
        (translatePredicate (atomic_list_concat ($bg-dir "/../pc-xp-ECAN/ecan_bg.pl") $bg-pl))
        (translatePredicate (ensure_loaded $bg-pl)))

;; Run both proof-search tiers in an abortable worker under one deadline.
!(progn (translatePredicate (working_dir $timed-dir))
  (translatePredicate (atomic_list_concat ($timed-dir "/pc_xp_timed.pl") $timed-pl))
  (translatePredicate (consult $timed-pl)))
!(translatePredicate (register_fun timed_obc_tiers_once))

!(import_prolog_functions_from_file (library petta_lib_logger lib_logger.pl)
                                    (logger-set-filepath
                                     logger-set-level
                                     logger-info
                                     logger-infof
                                     logger-debugf
                                     logger-tracef))

;; Import the propositional calculus corpus in the format
;; (MkIndexed INDEX (MkAxiom LABEL AXIOM))
;; (MkIndexed INDEX (MkTheorem LABEL PROOF THEOREM))
!(if (reverse-arguments)
     (import! &pc-idxd ../../metamath/propositional-calculus-reversed-arguments)
     (import! &pc-idxd ../../metamath/propositional-calculus))

;; Attention state and dynamics come from the metta-attention modules.
; Two pieces have to be supplied or the whole bank silently no-ops:
;   1. (library lib_spaces) provides match-count and find, which
;      setAv -> attentionValueChanged -> updateAf depend on.  Without it
;      the unregistered (match-count ...) call leaks as an inert term
;      into arithmetic: in isolation it throws
;      type_error(character, match-count), from compiled clauses it
;      silently no-ops, and STI stays frozen at its seed value forever.
;   2. write_csv_wrapper is CALLED by updateAf but DEFINED in
;      metta-attention/experiments/logger.metta.  That file is not
;      imported (its py-call CSV writer would fire on every setAv, i.e.
;      on the hot path); a no-op stub is supplied below instead.
;; With both in place setAv populates &typeSpace and &af, getSti/getLti
;; return real values, getAfAtoms yields the bounded attentional focus,
;; and the stock diffusion/rent agents run.
;; NOTE: setAv takes a bare ($sti $lti $vlti) tuple.  Passing ((AV ...))
;; matches no clause and silently does nothing.
!(import! &self (library lib_spaces))

;; (library lib_he) supplies `unify', which diffuseIncident uses to look up
; an atom's incident set.  Without it the call is unregistered and PeTTa's
; unknown-function fallback turns the whole (unify &incident ...) term into
; a DATA LIST, which is then diffused to as if its five elements -- `unify',
; `&incident', the pattern, ... -- were real neighbours.  Verified: with the
; old (L LABEL) key, (L a1i) at STI 300 diffused 19.0 apiece to six such
; phantom targets.
!(import! &self (library lib_he))

;; No-op stub for the AF's CSV hook -- see (2) above.  Must stay the ONLY
;; definition of write_csv_wrapper (do not import experiments/logger).
(= (write_csv_wrapper $x) ())

!(import! &self ../../../metta-attention/attention/AttentionParam)
!(import! &self ../../../metta-attention/attention-bank/utilities/helper-functions)
!(import! &self ../../../metta-attention/attention-bank/bank/importance-index/importance-index)
!(import! &self ../../../metta-attention/attention-bank/attention-value/getter-and-setter)
!(import! &self ../../../metta-attention/attention-bank/bank/attention-bank)
!(import! &self ../../../metta-attention/attention-bank/bank/attentional-focus/attentional-focus)
; Neighbors + baching are agent infrastructure, not optional extras:
; bach-p (baching) is how BOTH agents apply their results -- spreadImportance
; ends in (bach-p setStis $trades) and collectAFRent in (bach-p applyRent
; $input).  Unimported, bach-p does not reduce and every computed trade and
; rent charge is silently discarded.
!(import! &self ../../../metta-attention/attention/Neighbors)
!(import! &self ../../../metta-attention/attention/baching)
;; Each agent's arithmetic lives in its Base module, and each agent CALLS into
;; it: spreadImportance -> tradeList (ImportanceDiffusionBase), applyRent ->
;; calculateStiRent/calculateLtiRent (RentCollectionBaseAgent).  Importing the
;; agent without its base leaves those calls unreduced -- verified: the
;; collapse around tradeList then yields the literal one-element list
;; ((tradeList (...))), bach-p destructures that as a (source sti) pair and
;; calls (setStis tradeList <the-whole-list>), which throws inside
;; importanceBin and is swallowed by the catch in ecan-run-agents.  Net effect
;; without these two imports: both agents run to completion and move nothing.
!(import! &self ../../../metta-attention/attention/ImportanceDiffusionAgent/ImportanceDiffusionBase/ImportanceDiffusionBase)
!(import! &self ../../../metta-attention/attention/RentCollectionAgent/RentCollectionBaseAgent/RentCollectionBaseAgent)
;; Python helper used by the diffusion agent's top-k selection.
!(import! &self ../../../metta-attention/attention/ImportanceDiffusionAgent/getelement.py)
!(import! &self ../../../metta-attention/attention/ImportanceDiffusionAgent/AFImportanceDiffusionAgent/AFImportanceDiffusionAgent)
!(import! &self ../../../metta-attention/attention/RentCollectionAgent/AFRentCollectionAgent/AFRentCollectionAgent)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Attention economy (AttentionParam) ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; The shipped AttentionParam values are tuned for the wordnet/kg experiment;
;; three of them have to be re-pointed at this one or the agents, though live,
;; do nothing measurable.  They are changed through the stock
;; updateAttentionParam knob, not by editing AttentionParam.metta.

;; Diffusion budget split.  A source spends MAX_SPREAD_PERCENTAGE of its STI
;; per run; HEBBIAN_MAX_ALLOCATION_PERCENTAGE is the share of that budget
;; reserved for Hebbian links, the rest going to the atom's incident set and
;; outgoing set.  Our labels are opaque symbols with no incident or outgoing
;; structure, so at the shipped 0.05 the other 95% of the budget is reserved
;; for neighbours that do not exist and simply never leaves the source:
;; measured, one link moved 0.033% of the source's STI per run.  At 1.0 the
;; whole MAX_SPREAD_PERCENTAGE flows along Hebbian links, which is the only
;; topology this experiment has.
!(updateAttentionParam HEBBIAN_MAX_ALLOCATION_PERCENTAGE 1.0)

;; Rent and wages are two sides of one homeostat, both driven by how far
;; FUNDS_STI sits from TARGET_STI, in units of STI_FUNDS_BUFFER:
;;   wage = STI_ATOM_WAGE      * (1 + clamp((FUNDS_STI - TARGET_STI)/buffer, -1, 1))
;;   rent = StartingAtomStiRent* (1 + clamp((TARGET_STI - FUNDS_STI)/buffer, -0.99, 1))
;;          ... and is EXACTLY 0.0 whenever FUNDS_STI >= TARGET_STI.
;; FUNDS_STI is the un-disbursed reserve: every setAv moves (oldSti - newSti)
;; into it, so FUNDS_STI = STARTING_FUNDS_STI - the total STI held by atoms.
;;
;; MEASURED over a full run to 182: total STI issued is a little over 100000
;; and grows nearly linearly, roughly 700 per iteration.  The dominant source
;; is not the wage but ecan-seed-sti, which seeds each new lemma just above
;; the current maximum (~760 in practice) with a direct setAv that bypasses
;; the wage entirely.  Two consequences fix the parameters:
;;
;;  * At the shipped TARGET_STI of 10000, rent could only switch on once
;;    atoms held 90000 STI -- reached only in the last few iterations -- so
;;    rent was effectively pinned at zero for the whole run.
;;  * The buffer must be WIDER than the total excursion, or the wage rails.
;;    Verified at TARGET 60000 / buffer 40000: funds crossed below
;;    TARGET-buffer around iteration 120 and the wage sat at exactly 0.0 for
;;    the rest of the run -- stimulate then credits neither STI nor LTI, which
;;    silences the very signal the focus ranks on (iteration 158 missed the
;;    focused tier as a result), and funds ran to -2053.
;;
;; So: a pool with headroom for the ~100000 issued, a target crossed early
;; enough that rent shapes most of the run, and a buffer wide enough that the
;; wage tapers smoothly instead of hitting its rail.  Expected trajectory:
;; funds 250000 -> ~148000, wage 12.5 -> ~4.0, rent 0 -> ~1.6.
!(updateAttentionParam STARTING_FUNDS_STI 250000)
!(updateAttentionParam FUNDS_STI 250000)
!(updateAttentionParam TARGET_STI 220000)
!(updateAttentionParam STI_FUNDS_BUFFER 120000)

;;;;;;;;;;;;;;;;;;;;;;
;; Configure Logger ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Control space for the background ECAN daemon: liveness flag and the
;; resolved log path (see ecan-background).  Bound here because the logger
;; block below writes into it.
!(bind! &ecan-ctl (new-space))

!(logger-set-level (log-level))
;; (log-filepath) is resolved against working_dir so the log lands beside
;; this file rather than in whatever cwd run.sh was invoked from.
!(progn (translatePredicate (working_dir $this-dir))
        (translatePredicate (atomic_list_concat ($this-dir "/" (log-filepath)) $log-path))
        (logger-set-filepath $log-path)
        ;; Keep the resolved path: a hyperpose worker thread has to set the
        ;; logger up again for itself (see ecan-run-experiment), and cannot
        ;; recompute it -- working_dir does not resolve the same way there.
        (add-atom &ecan-ctl (logpath $log-path)))


;;;;;;;;;;;;;;;;;;;;;
;; ;;;;;;;;;;;;;;; ;;
;; ;; Functions ;; ;;
;; ;;;;;;;;;;;;;;; ;;
;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;
;; Concat ;;
;;;;;;;;;;;;

;; Concat atoms.  The implementation uses union-atom and assumes that
;; it preserves order.
(= (concat-atom $x $y) (union-atom $x $y))

;;;;;;;;;;;
;; Sized ;;
;;;;;;;;;;;

;; Associate a size to a term
(: Sized (-> $a Type))
(: MkSized (-> $n                       ; Size
               $a                       ; Object
               (Sized $a)))             ; Sized object

;; Access function
(= (Sized.object (MkSized $s $x)) $x)

;;;;;;;;;;;;;;;
;; Assertion ;;
;;;;;;;;;;;;;;;

;; Assertion, either axiom or theorem
(: Assertion Type)
(: MkAxiom (-> Symbol ; Label
               Atom   ; Axiom
               Assertion))
(: MkTheorem (-> Symbol ; Label
                 Atom   ; Proof
                 Atom   ; Theorem
                 Assertion))

;; Indexed assertion
(: Indexed Type)
(: MkIndexed (-> Number    ; Index
                 Assertion ; Axiom or Theorem
                 Indexed))

;;;;;;;;;;;
;; Maybe ;;
;;;;;;;;;;;

;; Define Maybe type
(: Maybe (-> $a Type))
(: Nothing (Maybe $a))
(: Just (-> $a (Maybe $a)))

;; Implement monad interface for return
;; (: Maybe.return (-> $a (Maybe $a)))
(= (Maybe.return $x) (Just $x))

;; Implement monad interface for bind
;; (: Maybe.bind (-> (Maybe $a) (-> $a (Maybe $b)) (Maybe $b)))
(= (Maybe.bind Nothing $f) Nothing)
(= (Maybe.bind (Just $x) $f) ($f $x))

;; Test Maybe
(: Maybe.test.foo (-> Number (Maybe String)))
(= (Maybe.test.foo $x) (if (== $x 42) (Just "42") Nothing))
!(test
  (Maybe.bind Nothing Maybe.test.foo)
  Nothing)
!(test
  (Maybe.bind (Just 0) Maybe.test.foo)
  Nothing)
!(test
  (Maybe.bind (Just 42) Maybe.test.foo)
  (Just "42"))

;;;;;;;;;;;;
;; Syntax ;;
;;;;;;;;;;;;

;; Return True iff the given term is an expression
;; (: is-expression (-> $a Bool))
(= (is-expression $x) (== (get-metatype $x) Expression))

;; Test is-expression
!(test
  (is-expression id)
  False)

;; Return True iff the given term is a lambda abstraction, meaning an
;; expression of the form (λ VARIABLES BODY)
;;
;; NEXT: simplify once issue
;; https://github.com/trueagi-io/PeTTa/issues/182 has been
;; solved.
;; (: is-lambda (-> $a Bool))
(= (is-lambda $x)
   (if (is-expression $x)
       (if (== () $x)
           False
           (== λ (car-atom $x)))
       False))

;; Test is-lambda
!(test
  (is-lambda A)
  False)
!(test
  (is-lambda (A B))
  False)
!(test
  (is-lambda (λ $x $y))
  True)

;; Return True iff the given term is an arrow type, meaning has the
;; following format (-> A), (-> A B), (-> A B C), etc.
;;
;; NEXT: simplify once issue
;; https://github.com/trueagi-io/PeTTa/issues/182 has been
;; solved.
;; (: is-arrow (-> Atom Bool))
(= (is-arrow $x)
   (if (is-expression $x)
       (if (== () $x)
           False
           (== -> (car-atom $x)))
       False))

;; Test is-arrow
!(test
  (is-arrow A)
  False)
!(test
  (is-arrow (F A B))
  False)
!(test
  (is-arrow (-> $a $b))
  True)

;; Return True iff the given term is a product, meaning an expression
;; of the form (, FIRST SECOND)
;;
;; NEXT: simplify once issue
;; https://github.com/trueagi-io/PeTTa/issues/182 has been
;; solved.
;; (: is-product (-> $a Bool))
(= (is-product $x)
   (if (is-expression $x)
       (if (== () $x)
           False
           (== , (car-atom $x)))
       False))

;; Test is-lambda
!(test
  (is-product A)
  False)
!(test
  (is-product (A B))
  False)
!(test
  (is-product (, A B))
  True)

;; Drop last element of a tuple
(= (drop-last $xs)
   (if (is-expression $xs)
       (if (== $xs ())
           (empty)
           (if (== (length $xs) 1)
               ()
               (let* ((($head $tail) (decons-atom $xs))
                      ($dlt (drop-last $tail)))
                 (cons-atom $head $dlt))))
       (empty)))

;; Test drop-last
!(test
  (drop-last (A))
  ())
!(test
  (drop-last (A B))
  (A))
!(test
  (drop-last (A B C))
  (A B))

;; Take last element of a tuple
(= (take-last $xs)
   (if (is-expression $xs)
       (if (== $xs ())
           (empty)
           (if (== (length $xs) 1)
               (car-atom $xs)
               (take-last (cdr-atom $xs))))
       (empty)))

;; Test take-last
!(test
  (take-last (A))
  A)
!(test
  (take-last (A B))
  B)

;; Get lambda variables.  Prune if not a lambda term.
(= (get-lambda-variables $term)
   (if (is-lambda $term)
       (let ($h $t) (decons-atom $term)
            (drop-last $t))
       (empty)))

;; Test get-lambda-variables
!(test
  (collapse (get-lambda-variables A))
  ())
!(test
  (get-lambda-variables (λ $x $y))
  ($x))
!(test
  (get-lambda-variables (λ $x1 $x2 $y))
  ($x1 $x2))

;; Get lambda body.  Prune if not a lambda term.
(= (get-lambda-body $term)
   (if (is-lambda $term)
       (take-last $term)
       (empty)))

;; Test get-lambda-body
!(test
  (collapse (get-lambda-body A))
  ())
!(test
  (get-lambda-body (λ $x A))
  A)
!(test
  (get-lambda-body (λ $x1 $x2 A))
  A)

;; Get arrow premises.  Prune if not an arrow.
(= (get-arrow-premises $term)
   (if (is-arrow $term)
       (let ($h $t) (decons-atom $term)
            (drop-last $t))
       (empty)))

;; Test get-lambda-variables
!(test
  (collapse (get-arrow-premises A))
  ())
!(test
  (get-arrow-premises (-> A B))
  (A))
!(test
  (get-arrow-premises (-> A B C))
  (A B))

;; Get lambda body.  Prune if not a lambda term.
(= (get-arrow-conclusion $term)
   (if (is-arrow $term)
       (take-last $term)
       (empty)))

;; Test get-lambda-body
!(test
  (collapse (get-arrow-conclusion A))
  ())
!(test
  (get-arrow-conclusion (-> A B))
  B)
!(test
  (get-arrow-conclusion (-> A B C))
  C)

;;;;;;;;;
;; Zip ;;
;;;;;;;;;

;; Zip two tuples with a given function.  It is assumed that both $xs
;; and $ys have the same length.
(= (zip-with $f $xs $ys)
   (if (== $xs ())
       ()
       (let* ((($xh $xt) (decons-atom $xs))
              (($yh $yt) (decons-atom $ys))
              ($zh ($f $xh $yh))
              ($zt (zip-with $f $xt $yt)))
         (cons-atom $zh $zt))))

;; Test zip-with
!(test
  (zip-with : () ())
  ())
!(test
  (zip-with : (x) (a))
  ((: x a)))
!(test
  (zip-with : (x y) (a b))
  ((: x a) (: y b)))

;;;;;;;;;;;;;;;;;;;;;;
;; Match over tuple ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Match pattern over a tuple of elements
(= (match' $tuple $ptrn $tmpl) (let $ptrn (superpose $tuple) $tmpl))

;; Test match' on empty tuple
!(test
  (collapse (match' () ($x $y) ($y $x)))
  ())

;; Test match' on singleton
!(test
  (collapse (match' ((A B)) ($x $y) ($y $x)))
  ((B A)))

;; Test match' on pair
!(test
  (collapse (match' ((A B) (C D)) ($x $y) ($y $x)))
  ((B A)
   (D C)))

;;;;;;;;;
;; Get ;;
;;;;;;;;;

;; Specialized match where the pattern is equal to the template
(= (get $spc $ptrn) (match $spc $ptrn $ptrn))

;; Specialized match' where the pattern is equal to the template
(= (get' $spc $ptrn) (match' $spc $ptrn $ptrn))

;;;;;;;;;;
;; Fold ;;
;;;;;;;;;;

;; Fold a tuple from right to left
;; (: foldr (-> (-> $a $b $b) $b $c $d))  ; NEXT: re-enable when fixed
(= (foldr $f $i $xs)
   (if (== $xs ())
       $i
       (let* ((($h $t) (decons-atom $xs))
              ($ft (foldr $f $i $t)))
         ($f $h $ft))))

;; Test foldr
!(test
  (foldr + 0 (1 2 3))
  6)

;;;;;;;;;;;;;;;
;; Successor ;;
;;;;;;;;;;;;;;;

;; Increment a number by 1.  Kept as a named function because `until'
;; takes its step as a function argument, and its test below passes this.
;; (: succ (-> Number Number))
(= (succ $n) (+ 1 $n))

;;;;;;;;;;;
;; Until ;;
;;;;;;;;;;;

;; Loop-like function ported from Haskell.  Iterate applying a given
;; function till some condition is reached.  You may want to make sure
;; that the predicate and the next function are deterministic,
;; otherwise the behavior of until might be a bit unpredictable.
;; (: until (-> (-> $a Bool)               ; Predicate
;;              (-> $a $a)                 ; Next
;;              $a                         ; Initial value
;;              $a))                       ; Final value
(= (until $p $f $x)
   (if ($p $x) $x (until $p $f ($f $x))))

;; Test until
(: test.equal-to-10 (-> Number Bool))
(= (test.equal-to-10 $x) (== 10 $x))
!(test
  (until test.equal-to-10 succ 0)
  10)

;;;;;;;;;;;;;;;
;; Term size ;;
;;;;;;;;;;;;;;;

;; Return the size of a term, which correspond to the number symbols,
;; variables and grounded subterms in the given term.
(= (term-size $x)
   (if (is-expression $x)
       (if (== $x ())
           0
           (let ($head $tail) (decons-atom $x)
                (+ (term-size $head) (term-size $tail))))
       1))

;; Test term-size
!(test
  (term-size A)
  1)
!(test
  (term-size ((R A) $x))
  3)
!(test
  (term-size (R A (S B C)))
  5)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Replace body of lambda by variable ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Take a term representing a proof and replace its body by a variable
;; (as to be able to rediscover it).  If it is a lambda abstraction,
;; then replace the lambda term body by a variable, other replace the
;; whole term by a variable.
;; (: replace-body-by-variable (-> $a $a))
(= (replace-body-by-variable $prf)
   (case (get-metatype $prf)
     ((Symbol $y)
      (Grounded $y)
      (Variable $y)
      (Expression
       (if (== () $prf)
           $y
           (case $prf
             (;; Unary lambda abstraction
              ((λ $x $bdy)
               (λ $x $y))
              ;; Binary lambda abstraction
              ((λ $x1 $x2 $bdy)
               (λ $x1 $x2 $y))
              ;; Ternary lambda abstraction
              ((λ $x1 $x2 $x3 $bdy)
               (λ $x1 $x2 $x3 $y))
              ;; Quaternary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $bdy)
               (λ $x1 $x2 $x3 $x4 $y))
              ;; Quintenary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $y))
              ;; Senary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $y))
              ;; Septenary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $y))
              ;; Octonary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $y))
              ;; Nonary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $y))
              ;; Denary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10 $y))
              ;; Otherwise
              ($else $y))))))))

;; Test replace-body-by-variable
!(test
  (replace-body-by-variable (λ mpi.2 mpi.1 (mpd mpi.2 (a1i mpi.1))))
  (λ mpi.2 mpi.1 $bdy))
!(test
  (replace-body-by-variable (mpd ax-1 ax-1))
  $bdy)

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Variable Introduction ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Replace a given symbol by a variable in a term.
;; (: replace-symbol-by-variable (-> Symbol $a $a))
(= (replace-symbol-by-variable $sym $term) (_replace-symbol-by-variable $sym $x $term))
;; (: _replace-symbol-by-variable (-> Symbol Variable $a $a))
(= (_replace-symbol-by-variable $sym $var $term)
   (case (get-metatype $term)
     ((Symbol (if (== $sym $term) $var $term))
      (Grounded $term)
      (Variable $term)
      (Expression (if (== $term ())
                      $term
                      (let* (;; Get head and tail of term
                             (($head $tail) (decons-atom $term))
                             ;; Recurs on head
                             ($nhd (_replace-symbol-by-variable $sym $var $head))
                             ;; Recurs on tail
                             ($ntl (_replace-symbol-by-variable $sym $var $tail)))
                        ;; Cons result
                        (cons-atom $nhd $ntl)))))))

;; Test replace-symbol-by-variable
!(test
  (replace-symbol-by-variable 𝜑 𝜑)
  $𝜑)
!(test
  (replace-symbol-by-variable 𝜑 (-> (→ 𝜑 (→ 𝜓 𝜒)) 𝜓 𝜑 𝜒))
  (-> (→ $𝜑 (→ 𝜓 𝜒)) 𝜓 $𝜑 𝜒))

;; Replace all greek letters by variables
;; (: replace-greeks-by-variables (-> $a $a))
(= (replace-greeks-by-variables $term)
   (foldr replace-symbol-by-variable $term (𝜑 𝜓 𝜒 𝜃 𝜏 𝜂 𝜁 𝜎 𝜌 𝜇 𝜆 𝜅)))

;; Test replace-greeks-by-variables
!(test
  (replace-greeks-by-variables 𝜑)
  $𝜑)
!(test
  (replace-greeks-by-variables (-> (→ 𝜑 (→ 𝜓 𝜒)) 𝜓 𝜑 𝜒))
  (-> (→ $𝜑 (→ $𝜓 $𝜒)) $𝜓 $𝜑 $𝜒))

;;;;;;;;;;;;;;;
;; Reduction ;;
;;;;;;;;;;;;;;;

;; Define space mapping proof and theorem to label, with
;; representation of the form:
;;
;; (Label PROOF THEOREM LABEL)
!(bind! &labels (new-space))

;;;;;;;;;;;;;;
;; Callback ;;
;;;;;;;;;;;;;;

;; Callback passed to the backward chainer.  It is called on every result,
;; intermediary included, and is the chainer's one extension point: it can
;; store results, or filter by returning (empty).
;;
;; It is the IDENTITY here, deliberately.  callback runs on the chainer's
;; hot path -- every intermediary result, millions of times in a long
;; search -- so anything done here is paid per search step; the bank's
;; setAv alone costs ~5.9x a plain space write.  Attention is credited
;; once per SUCCESSFUL proof instead (ecan-stimulate-proof), which is also
;; the better signal: "appeared in a proof that worked" rather than "was
;; touched while exploring a branch that failed".
;; (: callback (-> $a $a))
(= (callback (: $x $a)) (: $x $a))

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ECAN Helper Functions ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

;; --- Attention-bank access wrappers ---
;; Thin wrappers over the bank's getSti/getLti/getVlti/setAv/stimulate.
;; All are TOTAL: they return a value on every input and never reduce to
;; (empty), because a hard failure inside a progn/let chain silently
;; aborts the whole evaluation (see repro-empty-shortcircuits-evaluation).

;; The key a label is filed under in the attention bank.  It must be a
;; SYMBOL, and it must not be the bare label, for two independent reasons:
;;
;;  1. COLLISION.  The bank stores untagged pairs -- ($pattern ((AV ...)
;;     (Bin ...))) in &typeSpace and ($atom $sti) in &af -- so a label that
;;     collides with a registered PeTTa function reduces the pair away.  The
;;     corpus label `id' is the identity builtin: (id VALUE) evaluates to
;;     VALUE, the pattern is lost, and setAv silently fails -- verified:
;;     (setAv id (200.0 0.0 0.0)) returns empty while a tagged key succeeds.
;;     That empty propagated out of add-to-kbs and ended the until loop at
;;     iteration 19, the iteration that proves `id'.
;;
;;  2. IT MUST NOT BE AN EXPRESSION.  diffuseIncident treats every
;;     Expression atom in the focus as a link and diffuses
;;     MAX_SPREAD_PERCENTAGE * (1 - HEBBIAN_MAX_ALLOCATION_PERCENTAGE) of
;;     its STI to (cdr-atom $atom).  Under the previous (L LABEL) tag that
;;     made the bare LABEL a diffusion target -- a key nothing ever reads --
;;     so 38% of every focus atom's STI per run drained into unreachable
;;     shadow atoms, which then competed for &af slots.  Verified: (L a1i)
;;     at STI 300 handed 114.0 to the bare symbol a1i.  A Symbol has no
;;     outgoing set, so diffuseIncident yields nothing at all and diffusion
;;     flows purely along Hebbian links -- which is the only topology this
;;     experiment has.
;;
;; atom_concat is a PeTTa builtin, so this costs one Prolog atom_concat per
;; bank access.  Keep the "L-" prefix out of every OTHER space: &pc-rb,
;; &pc-ab, &pc-rb-af and &labels are all keyed by the raw label.
(= (ecan-key $l) (atom_concat "L-" $l))

;; Current STI of a label (0.0 when it has none).
(= (ecan-get-sti $l) (getSti (ecan-key $l)))

;; Set the STI of a label, replacing any previous value.
(= (ecan-set-sti $l $v)
   (with_mutex ecan_bank
     (let $k (ecan-key $l)
       (setAv $k ($v (getLti $k) (getVlti $k))))))

;; Current LTI of a label (0.0 when it has none).
(= (ecan-get-lti $l) (getLti (ecan-key $l)))

;; Labels of all inference rules currently in the knowledge base.
;;
;; NEVER call this (or any nullary function) directly as superpose's
;; argument.  translator.pl:134 special-cases (superpose ARG) when ARG is a
;; literal list at translation time -- and (ecan-kb-rule-labels) IS a
;; one-element list -- so it compiles to a single branch yielding the SYMBOL
;; `ecan-kb-rule-labels', never calling it.  The caller then evaluates
;; getSti/getLti on that symbol, which surfaces at run time as
;;   Domain error: function_input_arities(ecan-kb-rule-labels,[0]) ... found 1
;; Bind it with let first, as every call site below does.
(= (ecan-kb-rule-labels)
   (collapse (match &pc-rb (: $l $t) $l)))

;; Highest LTI currently recorded (0.0 if none), used to normalise the
;; LTI term when ranking rules for the focus.
(= (ecan-max-lti)
   (let $vs (collapse (let $ls (ecan-kb-rule-labels) (let $l (superpose $ls) (ecan-get-lti $l))))
     (if (== $vs ()) 0.0 (max-atom $vs))))

;; Stimulation for a label that appeared in a SUCCESSFUL proof.  The
;; bank's stimulate credits BOTH short term and long term importance in
;; one call (calculateSTIWage and calculateLTIWage), so no separate LTI
;; bump is needed -- unlike pc-xp-ECAN.metta, where the local port has to
;; do the two writes itself.  Called once per discovered proof (cold
;; path); `callback' deliberately does no stimulation at all, so this is
;; the only source of attention credit.  That is also the more meaningful
;; signal: it counts "appeared in a proof that worked", not "was touched
;; while exploring a branch that failed".
(= (ecan-stimulate-lasting $l $stimulus)
   (with_mutex ecan_bank (stimulate (ecan-key $l) $stimulus)))

;; Recursively stimulate all rule/axiom labels in a proof tree.  Total.
;; NOTE: the tree is walked with an explicit car/cdr recursion -- passing
;; (superpose (cdr-atom $prf)) as the recursive argument hands the callee
;; the UNEVALUATED superpose-expression, which re-wraps itself forever
;; (verified hang).
(= (ecan-stimulate-proof $prf)
   (if (== (get-metatype $prf) Symbol)
       (ecan-stimulate-lasting $prf (ecan-proof-stimulus))
       (if (and (== (get-metatype $prf) Expression)
                (not (== () $prf)))
           (ecan-stimulate-proof-elems $prf)
           ())))

;; Walk a tuple of proof sub-terms, stimulating each.  Total.
(= (ecan-stimulate-proof-elems $elems)
   (if (== $elems ())
       ()
       (progn
        (ecan-stimulate-proof (car-atom $elems))
        (ecan-stimulate-proof-elems (cdr-atom $elems)))))

;; Take the first $n elements of a tuple.  Guard with <= 0 rather than
;; == 0: a fractional or negative bound would step straight past an
;; equality test and recurse until the tuple ran out (or forever).
(= (take-n $n $tuple)
   (if (or (<= $n 0) (== $tuple ()))
       ()
       (cons-atom (car-atom $tuple)
                  (take-n (- $n 1) (cdr-atom $tuple)))))

;; Alternate two ranked tuples.  Deduplicating and truncating this result
;; gives neither selector priority and fills overlap-created vacancies.
(= (interleave-atom $x $y)
   (if (== $x ())
     $y
     (if (== $y ())
       $x
       (cons-atom (car-atom $x)
            (cons-atom (car-atom $y)
                 (interleave-atom (cdr-atom $x)
                          (cdr-atom $y)))))))

;; Focus ranking score: short-term importance (what is hot now, driven by
;; recency seeding and stimulation) plus normalised long-term importance
;; (what has repeatedly proved useful).  Negated so a plain ascending
;; sort-atom puts the best rules first.
(= (ecan-rule-score $lbl $max-lti)
   (* -1.0
      (+ (ecan-get-sti $lbl)
         (if (<= $max-lti 0.0)
             0.0
             (* (ecan-lti-weight)
                (* (ecan-sti-ceiling)
                   (/ (ecan-get-lti $lbl) $max-lti)))))))

;; R-tagged intermediate: an untagged ($lbl $typ) 2-tuple reduces when
;; the label collides with a builtin (e.g. the corpus label `id`).
(= (ecan-scored-rules)
   (let $max-lti (ecan-max-lti)
     (collapse
      (let (R $lbl $typ) (match &pc-rb (: $lbl $typ) (R $lbl $typ))
        ((ecan-rule-score $lbl $max-lti) $lbl $typ)))))

;; Rebuild the attention-focused rule base as the top (ecan-focus-size)
;; inference rules by STI.  Axioms live in &pc-ab and are always
;; available; only the *rules* the search may apply are restricted here.
;; This is what makes &pc-rb-af genuinely smaller than &pc-rb, so the
;; focused-first search can miss and the full fallback becomes live.
(= (ecan-rebuild-focused-rb)
   (with_mutex ecan_bank
   (progn
    ;; Clear old AF rule-base entries
    (let $old (collapse (match &pc-rb-af $e $e))
      (collapse (let $e (superpose $old) (remove-atom &pc-rb-af $e))))
    ;; Keep the stock attentional focus (&af) sized to our focus, so
    ;; getAfAtoms and this rule focus stay in step.  updateAf evicts the
    ;; lowest-STI atom once &af reaches MAX_AF_SIZE.
    (updateAttentionParam MAX_AF_SIZE (ecan-focus-size))
    ;; Select the top-N rules and populate &pc-rb-af
    (let* (($scored (ecan-scored-rules))
           ($sorted (sort-atom $scored))
           ($top-n (take-n (ecan-focus-size) $sorted)))
      (collapse
       (let ($neg-sti $lbl $typ) (superpose $top-n)
         (add-atom &pc-rb-af (: $lbl $typ))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ECAN Pipeline: Hebbian links (lean port)   ;;
;; plus the STOCK diffusion and rent agents   ;;
;;                                            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; The stock agents select their targets via getAfAtoms, which reads the &af
;; space.  &af is populated by updateAf (called from setAv), and updateAf
;; needs two things this file supplies at import time: (library lib_spaces)
;; for the match-count/find primitives, and a no-op write_csv_wrapper stub in
;; place of metta-attention/experiments/logger.metta.  With both present the
;; bank is live, getAfAtoms returns a bounded attentional focus, and the
;; stock agents run -- AFImportanceDiffusionAgent-Run and
;; AFRentCollectionAgent-run are invoked directly in ecan-run-agents.
;;
;; What stays local, and why: Hebbian link creation/update (below), because
;; HebbianCreationAgent-Run draws its sources from the AF rather than from
;; the labels co-used in a proof, which is the signal we actually have;
;; &pc-rb-af, the RULE focus the two-tier search uses, which is a different
;; population from the bank's &af (that holds every atom with an attention
;; value).
;;
;; Both stock agents call into modules the agent files do not import
;; themselves -- baching, ImportanceDiffusionBase, RentCollectionBaseAgent,
;; and lib_he -- so those are imported here alongside the agents.  See the
;; import block for what each one silently breaks when it is missing.

;; All symbols occurring in a proof tree, as a flat tuple (explicit
;; car/cdr walk -- see the ecan-stimulate-proof note on superpose).
(= (ecan-proof-symbols $prf)
   (if (== (get-metatype $prf) Symbol)
       ($prf)
       (if (and (== (get-metatype $prf) Expression)
                (not (== () $prf)))
           (ecan-proof-symbols-elems $prf)
           ())))

(= (ecan-proof-symbols-elems $elems)
   (if (== $elems ())
       ()
       (concat-atom (ecan-proof-symbols (car-atom $elems))
                    (ecan-proof-symbols-elems (cdr-atom $elems)))))

;; True iff the label is a rule or axiom in the knowledge bases (filters
;; out λ, premise variables like mp2.1, etc.).
(= (ecan-is-kb-label $l)
   (if (== () (collapse (match &pc-rb (: $l $t) True)))
       (not (== () (collapse (match &pc-ab (: $l $t) True))))
       True))

;; Unique KB labels used in a proof.
(= (ecan-proof-kb-labels $prf)
   (let $syms (unique-atom (ecan-proof-symbols $prf))
     (collapse
      (let $s (superpose $syms)
        (if (ecan-is-kb-label $s) $s (empty))))))

;; Create or strengthen the Hebbian link SRC->TGT (HebbianCreationAgent's
;; addHebbian initialises at (0.5 0.1); HebbianUpdatingAgent blends the
;; strength toward fresh evidence with TC_DECAY_RATE — here the direct
;; co-use of both labels in one proof counts as evidence 1.0).
;; Hebbian links are kept in the exact shape diffuseHebbian matches:
;;   ((ASYMMETRIC_HEBBIAN_LINK SRC TGT) (STV MEAN CONF))
;; Any other encoding makes the stock diffusion agent find nothing and
;; spread nothing.  SRC and TGT are BANK KEYS (ecan-key), not raw labels:
;; diffuseHebbian matches this space against atoms taken from getAfAtoms,
;; so an endpoint stored as the raw label can never match and the whole
;; link store is invisible to the agent.  New values must be computed into
;; variables first -- add-atom stores its argument unevaluated.
(= (ecan-update-hebbian-pair $a $b)
   (case (once (match &hebbian-stock ((ASYMMETRIC_HEBBIAN_LINK $a $b) (STV $m $c))
                      ($m $c)))
     ((($m $c)
       (let* (($decay (ecan-hebbian-decay))
              ($new-m (+ (* $decay 1.0) (* (- 1.0 $decay) $m)))
              ($new-c (min-atom ((+ $c 0.05) 0.95))))
         (progn
          (remove-atom &hebbian-stock
                       ((ASYMMETRIC_HEBBIAN_LINK $a $b) (STV $m $c)))
          (add-atom &hebbian-stock
                    ((ASYMMETRIC_HEBBIAN_LINK $a $b) (STV $new-m $new-c))))))
      (Empty (add-atom &hebbian-stock
                       ((ASYMMETRIC_HEBBIAN_LINK $a $b) (STV 0.5 0.1)))))))

;; Create/strengthen links between every ordered pair of distinct labels
;; co-used in a proof (HebbianCreationAgent semantics over the co-focused
;; set — here the co-used set, the direct evidence available to us).
;; Takes RAW labels and converts to bank keys here, so callers keep working
;; in the label vocabulary every other space uses.
(= (ecan-update-hebbian-links $labels)
   (collapse
    (let* (($a (superpose $labels))
           ($b (superpose $labels)))
      (if (== $a $b)
          ()
          (let* (($ka (ecan-key $a))
                 ($kb (ecan-key $b)))
            (ecan-update-hebbian-pair $ka $kb))))))

;; Labels currently in the attentional focus (&pc-rb-af).
(= (ecan-focus-labels)
   (collapse (match &pc-rb-af (: $l $t) $l)))

;; Run the ECAN pipeline between theorem iterations: diffusion spreads STI
;; from hot rules to their historical collaborators, and rent decays the
;; focus so stale rules drop out of the top-N.  catch keeps the proof
;; search alive if an edge state throws.
;; One background sweep.  Kept separate from ecan-run-agents so the daemon
;; does not emit the per-iteration diagnostic line on every tick.
;; The WHOLE sweep is serialised against the main thread's bank access.
;;
;; setAv is an unguarded read-modify-write on &typeSpace: it matches the
;; existing entry, remove-atoms it, then add-atoms the new one.  Two threads
;; interleaving there means one removes an entry the other already removed;
;; the loser's remove-atom fails, the enclosing let* fails, setAv returns
;; EMPTY, and that empty propagates out through ecan-set-sti -> add-to-kbs
;; -> process-assertion and silently ends the until loop.
;;
;; MEASURED without this: two full runs to 182 -- one completed with 176
;; proofs, the other stopped dead at iteration 77 with 72 proofs, no error
;; and no "No proof found" line.  The loop simply terminated mid-corpus.
;;
;; SWI's with_mutex is recursive per-thread, so nesting guarded calls is safe.
(= (ecan-sweep)
   (with_mutex ecan_bank
   (progn
    (add-atom &ecan-ctl (tick))
    (catch (collapse (AFImportanceDiffusionAgent-Run &incident &hebbian-stock)))
    (catch (collapse (AFRentCollectionAgent-run)))
    (if (ecan-daemon-steers-search) (catch (ecan-rebuild-focused-rb)) ()))))

;; The background loop.  Exits when the foreground clears the running flag.
(= (ecan-daemon)
   (if (== () (collapse (match &ecan-ctl (running True) 1)))
       (progn (add-atom &ecan-ctl (stopped)) done)
       (progn
        (catch (ecan-sweep))
        (catch (translatePredicate (sleep (ecan-daemon-interval))))
        (ecan-daemon))))

;; Wait (bounded) for the daemon thread to observe the cleared flag and exit.
;; Without this the process can halt while the daemon is mid-sleep, SWI
;; unwinds the thread with unwind(halt(0)), and that surfaces as a warning
;; from a thread that had nothing wrong with it.
(= (ecan-await-daemon $tries)
   (if (<= $tries 0)
       timeout
       (if (== () (collapse (match &ecan-ctl (stopped) 1)))
           (progn (catch (translatePredicate (sleep 0.05)))
                  (ecan-await-daemon (- $tries 1)))
           stopped)))

(= (ecan-daemon-stop)
   (progn
    (collapse (match &ecan-ctl (running True) (remove-atom &ecan-ctl (running True))))
    (ecan-await-daemon 200)))

;; Foreground branch: the experiment, then stop the daemon so hyperpose can join.
;;
(= (ecan-run-agents)
   (if (ecan-use-agents)
       (progn
        ;; Stock agents.  AFImportanceDiffusionAgent-Run takes TWO spaces
        ;; (incident, hebbian) -- calling it with one matches no clause and
        ;; silently does nothing.  Hebbian links are maintained in the
        ;; stock ((ASYMMETRIC_HEBBIAN_LINK src tgt) (STV mean conf)) form.
        (catch (collapse (AFImportanceDiffusionAgent-Run &incident &hebbian-stock)))
        (catch (collapse (AFRentCollectionAgent-run)))
        ;; Diagnostic only -- but a single empty result anywhere in the
        ;; argument tuple makes the whole logger-debugf fail, which
        ;; propagates out of this progn and silently ends the until loop.
        ;; So every bank lookup here is collapsed: a diagnostic must never
        ;; be able to abort the experiment.
        (if (ecan-log-tier)
            (let $focus (ecan-focus-labels)
              (let* (($sample (if (== $focus ()) none (car-atom $focus)))
                     ($af (collapse (getAfAtoms)))
                     ($sti (if (== $sample none)
                               (0.0)
                               (collapse (ecan-get-sti $sample)))))
                (logger-debugf "  [ecan] af-size=%w sample=%w sti=%w funds=%w rent=%w wage=%w"
                               ((if (== $af ()) 0 (size-atom (car-atom $af)))
                                $sample
                                (if (== $sti ()) 0.0 (car-atom $sti))
                                (getAttentionParam FUNDS_STI)
                                (calculateStiRent (getAttentionParam StartingAtomStiRent))
                                (calculateSTIWage)))))
            ()))
       ()))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; WILLIAM half of the union      ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Each label's ORIGINAL corpus statement, variables still spelled as Greek
;; letters.  These cannot come from &pc-rb: add-to-kbs runs
;; replace-greeks-by-variables first, so those copies repr as `$_3322', and
;; infcontrol identifies a variable by a leading GREEK character.  Measured,
;; feeding gensyms instead scores 0.171 where Greek scores 0.00828 -- a 20x
;; error, silent and plausible-looking.
!(bind! &pc-orig (new-space))

;; Python bridge (shared with ../pc-xp-william; it shells out to infcontrol's
;; predict_cli inside the venv, so the system python needs no extra packages).
!(import! &self ../pc-xp-william/william_rank.py)

;; HOW MANY EACH SELECTOR NOMINATES.
;;
;; Deliberately smaller than (ecan-focus-size).  Measured on the first union
;; run: with each nominating 40 the two agreed on only 11 rules -- 28% -- so
;; the union came to ~69 and every tier-1 search paid for 69 rules instead of
;; 40.  That bought the best coverage of any variant (96.0% hits, 7 misses)
;; but cost time: 7m24s against ECAN's 4m42s on its own 40.
;;
;; So shrink each nomination until the UNION is about 40, the same search
;; budget ECAN uses alone.  With ~28% agreement, union ~= 1.725 * n, so
;; n ~= 23 lands the union near 40.  0.17 * 135 = 22.
;;
;; This isolates the question the first run could not answer: is the union's
;; advantage the DIVERSITY of two disagreeing rankings, or just a bigger
;; focus?  At an equal budget, only diversity is left to explain a win.
(= (union-nominate-fraction) 0.17)
(= (union-nominate-min) 15)

(= (union-nominate-size)
   (let $n (size-atom (collapse (match &pc-rb (: $l $t) $l)))
     (max (union-nominate-min)
          (trunc-math (* (union-nominate-fraction) $n)))))

;; Pair each probability with its label, negated, so a plain ascending
;; sort-atom puts the most probable first.  W-tagged so a label colliding
;; with a builtin (the corpus label `id') cannot reduce the tuple away.
(= (william-zip $pairs $scores)
   (if (or (== $pairs ()) (== $scores ()))
       ()
       (let* ((($ph $pt) (decons-atom $pairs))
              (($sh $st) (decons-atom $scores))
              ((P $lbl $stmt) $ph)
              ($neg (* -1.0 $sh))
              ($rest (william-zip $pt $st)))
         (cons-atom (W $neg $lbl) $rest))))

;; WILLIAM's complete ranking for this goal.  Returns a plain tuple of labels,
;; or () if the predictor is unavailable.
(= (william-ranked-labels $goal)
   (let $pairs (collapse (match &pc-rb (: $l $t)
                           (let $s (match &pc-orig (Orig $l $os) $os) (P $l $s))))
     (if (== $pairs ())
         ()
         (let* (($rule-labels (collapse (match &pc-rb (: $rl $rt) $rl)))
                ($axiom-labels (collapse (match &pc-ab (: $al $at) $al)))
                ($theory-labels (concat-atom $rule-labels $axiom-labels))
                ($raw
             (catch
              (let* (($scores (py-call (william_rank.score (repr $goal)
                                                           (repr $pairs)
                                                           (repr $theory-labels))))
                     ($scored (william-zip $pairs $scores))
                   ($sorted (sort-atom $scored)))
                 (collapse (let (W $neg $lbl) (superpose $sorted) $lbl))))))
           (if (and (is-expression $raw) (== (car-atom $raw) Error)) () $raw)))))

          ;; ECAN's complete ranking, as a plain tuple of labels.
          (= (ecan-ranked-labels)
   (let* (($scored (ecan-scored-rules))
              ($sorted (sort-atom $scored)))
            (collapse (let ($neg-sti $lbl $typ) (superpose $sorted) $lbl))))

          ;; Install one selector result and emit aggregate and full-ranking data.
          (= (install-focused-rb $idx $theorem-label $mode
                     $e-ranked $w-ranked $e-nominated $w-nominated $selected)
   (progn
    (let $old (collapse (match &pc-rb-af $e $e))
      (collapse (let $e (superpose $old) (remove-atom &pc-rb-af $e))))
    (updateAttentionParam MAX_AF_SIZE (ecan-focus-size))
              (collapse
            (let $lbl (superpose $selected)
              (let $ty (match &pc-rb (: $lbl $t) $t)
                (add-atom &pc-rb-af (: $lbl $ty)))))
              (if (ecan-log-tier)
               (progn
                (logger-infof "  [union] ecan=%w will=%w union=%w"
                     ((size-atom $e-nominated)
                      (size-atom $w-nominated)
                      (size-atom $selected)))
                (logger-infof "  [ranking] index=%w theorem=%w mode=%w budget=%w ecan=%w william=%w selected=%w"
                     ($idx $theorem-label $mode (ecan-focus-size)
                      $e-ranked $w-ranked $selected)))
               ())))

          ;; Rebuild &pc-rb-af with exactly the same dynamic budget in all three modes.
          ;; Union alternates full rankings before deduplication, then fills to budget.
          (= (union-rebuild-focused-rb $idx $theorem-label $goal)
             (if (== (selector-mode) ecan)
              (let* (($e-ranked (ecan-ranked-labels))
                  ($selected (take-n (ecan-focus-size) $e-ranked)))
                (install-focused-rb $idx $theorem-label ecan
                        $e-ranked () $selected () $selected))
              (if (== (selector-mode) william)
               (let* (($w-ranked (william-ranked-labels $goal))
                   ($selected (take-n (ecan-focus-size) $w-ranked)))
                 (install-focused-rb $idx $theorem-label william
                         () $w-ranked () $selected $selected))
               (let* (($e-ranked (ecan-ranked-labels))
                   ($w-ranked (william-ranked-labels $goal))
                   ($nominate-n (union-nominate-size))
                   ($e-nominated (take-n $nominate-n $e-ranked))
                   ($w-nominated (take-n $nominate-n $w-ranked))
                   ($interleaved (interleave-atom $e-ranked $w-ranked))
                   ($selected (take-n (ecan-focus-size)
                          (unique-atom $interleaved))))
                 (install-focused-rb $idx $theorem-label union
                         $e-ranked $w-ranked
                         $e-nominated $w-nominated $selected)))))

;;;;;;;;;;;;;;;;;;;;;;
;; Backward chainer ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Backward chainer with support for lambda abstraction at the entry
;; point (no recursive search on lambda terms).  The knowledge is
;; decomposed into a rule base and an axiom base because we know we
;; never need to search both at the same time, only one or the other.
;;
;; The search is bounded by PROOF SIZE.  A depth-bounded variant (bc/_bc,
;; taking a Nat) used to sit alongside this one; it was measurably slower
;; and never selected, and has been removed.
;;
;; The arguments are:
;;
;; * Rule base: reference to a space containing rules in the format
;;
;; (: NAME (-> PREMISE1 ... CONCLUSION))
;;
;; * Axiom base: reference to a space containing axioms in the format
;;
;; (: NAME AXIOM)
;;
;; * Callback: function called on every result, final or intermediary.
;;   It can store results, or act as a filter by returning (empty).
;;
;; * Maximum proof size: bound on the size of the generated proof term.
;;
;; * Query: a metta term of the form (: <PROOF> <THEOREM>) where
;;   <PROOF> and <THEOREM> may contain free variables that may be
;;   filled by the backward chainer.
;;
;; A result is the query with its variables grounded, fully or
;; partially.  If multiple results are possible, they are returned as
;; a superposition.

;; ;; Entry point
;; (: obc (-> $a                            ; Rule base space
;;            $b                            ; Axiom base space
;;            (-> $c $c)                    ; Callback
;;            Number                        ; Maximum proof size
;;            $c                            ; Query
;;            $c))                          ; Result
(= (obc $rb $ab $cb $mps (: $prf $thrm))
   (progn
    (logger-tracef "Call (lambda): (obc %w %w %w %w (: %w %w))"
                   ($rb $ab $cb $mps $prf $thrm))
    (if (< 0 $mps)
        (if (is-expression $prf)
            ;; Proof is an expression, check whether it is a lambda term
            (if (== () $prf)
                ;; Proof is empty and already fully defined
                (: $prf $thrm)
                ;; Proof is not empty
                (if (is-lambda $prf)
                    ;; Proof is a lambda term
                    (let* (;; Get variables, body, premises and conclusion
                           ($xs (get-lambda-variables $prf))
                           ($as (get-arrow-premises $thrm))
                           ($y (get-lambda-body $prf))
                           ($b (get-arrow-conclusion $thrm))
                           ;; Build environment
                           ($env (zip-with : $xs $as))
                           ;; Calculate maximum body size (decount λ
                           ;; and variables)
                           ($mbs (- $mps (+ (length $xs) 1)))
                           ;; Call _obc to proof conclusion given environment
                           ((MkSized $bdysize (: $y $b))
                            (_obc $rb $ab $cb $env $mbs (: $y $b)))
                           ;; Reconstruct lambda term
                           ($prf (cons-atom λ (concat-atom $xs ($y))))
                           ;; Reconstruct arrow
                           ($thrm (cons-atom -> (concat-atom $as ($b)))))
                      ;; Output
                      (: $prf $thrm))
                    ;; Not a lambda term, merely call _obc
                    (Sized.object (_obc $rb $ab $cb () $mps (: $prf $thrm)))))
            ;; Proof is not an expression, merely call _obc
            (Sized.object (_obc $rb $ab $cb () $mps (: $prf $thrm))))
        ;; If maximum proof size is 0, then no proof can possibly be found
        (empty))))

;; Recursive search.  Outputs a sized (: PROOF THEOREM) result so
;; _obc_prod can thread the shrinking budget across premises.
;;
;; NEXT: re-enable when fixed
;; (: _obc (-> $a                            ; Rule base space
;;             $b                            ; Axiom base space
;;             (-> $c $c)                    ; Callback
;;             (List $b)                     ; Environment
;;             Number                        ; Maximum proof size
;;             $c                            ; Query
;;             (Sized $c)))                  ; Result

;; Base cases

;; Match the axiom base
(= (_obc $rb $ab $cb $env $mps (: $x $a))
   (if (< 0 $mps)
       (progn
        ;; (logger-tracef "Call (ab): (_obc %w %w %w %w %w (: %w %w))"
        ;;                ($rb $ab $cb $env $mps $x $a))
        (MkSized 1 ($cb (get $ab (: $x $a)))))
       (empty)))

;; Match the environment
(= (_obc $rb $ab $cb $env $mps (: $x $a))
   (if (< 0 $mps)
       (progn
        ;; (logger-tracef "Call (env): (_obc %w %w %w %w %w (: %w %w))"
        ;;                ($rb $ab $cb $env $mps $x $a))
        (MkSized 1 ($cb (get' $env (: $x $a)))))
       (empty)))

;; Recursive steps

;; Product.  It is used internally by proof application to iterate
;; over premises.  Due to being only used internally, we do not
;; account for the size of the product itself `,`.  The product is
;; associative but is assumed here to only take right associative
;; forms like (, x (, y z)).
(= (_obc_prod $rb $ab $cb $env $mps (: (, $x $y) (, $a $b)))
   (progn
    ;; (logger-tracef "Call (prod): (_obc_prod %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env $mps (: (, $x $y) (, $a $b))))
    (let* (;; Recurse on first component
           ((MkSized $xps (: $x $a)) (_obc $rb $ab $cb $env $mps (: $x $a)))
           ;; Calculate remaining maximum size
           ($rms (- $mps $xps))
           ;; Recurse on second component
           ((MkSized $yps (: $y $b))
            (if (is-product $y)
                (_obc_prod $rb $ab $cb $env $rms (: $y $b))
                (_obc $rb $ab $cb $env $rms (: $y $b)))))
      ;; Output sized proof (sum up sizes of all subproofs)
      (MkSized (+ $xps $yps) (: (, $x $y) (, $a $b))))))

;; Unary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x) $b))
   (if (< 1 $mps)
       (progn
        ;; (logger-tracef "Call (app-1): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x) $b)))
        (let* (;; Query unary rule
               ((: $f (-> $a $b)) (get $rb (: $f (-> $a $b))))
               ;; Recurse on premise
               ((MkSized $xps (: $x $a))
                (_obc $rb $ab $cb $env (- $mps 1) (: $x $a))))
          ;; Output sized proof (size of proof of premise + rule)
          (MkSized (+ $xps 1) ($cb (: ($f $x) $b)))))
       (empty)))

;; Binary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2) $b))
   (if (< 2 $mps)
       (progn
        ;; (logger-tracef "Call (app-2): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2) $b)))
        (let* (;; Query binary rule
               ((: $f (-> $a1 $a2 $b)) (get $rb (: $f (-> $a1 $a2 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 $x2) (, $a1 $a2)))
                (_obc_prod $rb $ab $cb $env (- $mps 1) (: (, $x1 $x2) (, $a1 $a2)))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2) $b)))))
       (empty)))

;; Ternary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3) $b))
   (if (< 3 $mps)
       (progn
        ;; (logger-tracef "Call (app-3): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3) $b)))
        (let* (;; Query ternary rule
               ((: $f (-> $a1 $a2 $a3 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 $x3)) (, $a1 (, $a2 $a3))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 $x3)) (, $a1 (, $a2 $a3))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3) $b)))))
       (empty)))

;; Quaternary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4) $b))
   (if (< 4 $mps)
       (progn
        ;; (logger-tracef "Call (app-4): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4) $b)))
        (let* (;; Query quaternary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 $x4)))
                                 (, $a1 (, $a2 (, $a3 $a4)))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 $x4)))
                              (, $a1 (, $a2 (, $a3 $a4)))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4) $b)))))
       (empty)))

;; Quintenary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5) $b))
   (if (< 5 $mps)
       (progn
        ;; (logger-tracef "Call (app-5): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5) $b)))
        (let* (;; Query quintenary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 $x5))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 $a5))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 $x5))))
                              (, $a1 (, $a2 (, $a3 (, $a4 $a5))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5) $b)))))
       (empty)))

;; Senary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b))
   (if (< 6 $mps)
       (progn
        ;; (logger-tracef "Call (app-6): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b)))
        (let* (;; Query senary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 $x6)))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 $a6)))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 $x6)))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 $a6)))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b)))))
       (empty)))

;; Septenary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b))
   (if (< 7 $mps)
       (progn
        ;; (logger-tracef "Call (app-7): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b)))
        (let* (;; Query septenary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 $x7))))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 $a7))))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 $x7))))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 $a7))))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b)))))
       (empty)))

;; Octonary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b))
   (if (< 8 $mps)
       (progn
        ;; (logger-tracef "Call (app-8): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b)))
        (let* (;; Query octonary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 $x8)))))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 $a8)))))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 $x8)))))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 $a8)))))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b)))))
       (empty)))

;; Nonary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b))
   (if (< 9 $mps)
       (progn
        ;; (logger-tracef "Call (app-9): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b)))
        (let* (;; Query nonary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9))))))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9))))))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b)))))
       (empty)))

;; Denary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b))
   (if (< 10 $mps)
       (progn
        ;; (logger-tracef "Call (app-10): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b)))
        (let* (;; Query denary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9))))))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 (, $x9 $x10)))))))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 (, $a9 $a10)))))))))))))
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b)))))
       (empty)))

;;;;;;;;;;;;;;;;;
;; ;;;;;;;;;;; ;;
;; ;; Tests ;; ;;
;; ;;;;;;;;;;; ;;
;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;
;; Helpers ;;
;;;;;;;;;;;;;

;; In case the input number is something, then return True iff it is
;; equal of the maximum index of the propositional calculus indexed
;; corpus.  If the input number is nothing, then return True as well
;; because it means that a verification has failed and thus the
;; experiment should be aborted.
;; (: equal-to-upidx-or-nothing (-> (Maybe Number) Bool))
(= (equal-to-upidx-or-nothing $idxm)
   (case $idxm
     (((Just $idx) (== (up-to-idx) $idx))
      (Nothing True))))

;; Create a propositional calculus rule base, containing type
;; theoretic representation of rules like
;;
;; (: ax-mp (-> (→ $𝜑 $𝜓) $𝜑 $𝜓))
!(bind! &pc-rb (new-space))

;; Create a propositional calculus axiom base, containing type
;; theoretic representation of axioms like
;;
;; (: ax-1 (→ $𝜑 (→ $𝜓 $𝜑)))
;; (: ax-2 (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒))))
;; (: ax-3 (→ (→ (¬ $𝜑) (¬ $𝜓)) (→ $𝜓 $𝜑)))
!(bind! &pc-ab (new-space))

;; Create the attention-focused rule base.  It is rebuilt before each
;; theorem search from the labels currently carrying an ECAN attention
;; value (see ecan-rebuild-focused-rb) and searched before the full
;; &pc-rb.
!(bind! &pc-rb-af (new-space))

;; Hebbian link space: (Heb SRC TGT MEAN CONF) records that labels SRC and
;; TGT were used together in a discovered proof (asymmetric, like
;; ASYMMETRIC_HEBBIAN_LINK in the HebbianCreationAgent).  Importance
;; diffusion spreads STI along these links so rules historically co-used
;; with currently-hot rules are pre-activated into the focus.
!(bind! &hebbian-stock (new-space))

;; Incident space for the diffusion agent's non-Hebbian spreading.  Our
;; labels are opaque symbols with no incoming/outgoing structure, so this
;; stays empty; diffusion therefore flows purely along Hebbian links.
!(bind! &incident (new-space))



;; Enable occurs check to detect cycles in unification (note that it
;; returns a variable, this is normal)
!(translatePredicate (set_prolog_flag occurs_check True))

;; Add assertion to knowledge bases.  If it is an axiom then add it to
;; pc-ab.  If it is a rule then add it to pc-rb.  Additionally replace
;; greek letters by variables.
(= (add-to-kbs $label $stmt)
   (let $stmt-with-vars (replace-greeks-by-variables $stmt)
     (let $is-rule (is-arrow $stmt)
       (progn
        ;; Add to rule base or axiom base
        (if $is-rule
            (add-atom &pc-rb (: $label $stmt-with-vars))
            (add-atom &pc-ab (: $label $stmt-with-vars)))
        ;; WILLIAM scores the pre-substitution form (see &pc-orig).
        (add-atom &pc-orig (Orig $label $stmt))
        ;; ECAN: seed the label's STI.  Rules are seeded by RECENCY --
        ;; just above the current maximum -- so a freshly proved lemma
        ;; enters the attentional focus immediately (see ecan-seed-bonus).
        ;; Axioms keep the plain seed; they are in &pc-ab and always
        ;; available to the search regardless of focus.
        (if (ecan-use-agents)
            (ecan-set-sti $label
                          (if $is-rule (ecan-seed-sti) (ecan-axiom-sti)))
            ())))))

;; Seed STI for a newly proved lemma: just above the highest STI in the
;; system, with (ecan-rule-sti) as a floor for the very first lemmas.
(= (ecan-seed-sti)
   (let $vals (collapse (let $ls (ecan-kb-rule-labels) (let $l (superpose $ls) (ecan-get-sti $l))))
     (if (== $vals ())
         (ecan-rule-sti)
         (max (ecan-rule-sti) (+ (max-atom $vals) (ecan-seed-bonus))))))

;; Add proof and theorem to label mapping to labels space
(= (add-to-labels $proof $theorem $label)
   (progn
    ;; (logger-tracef "Call: (add-to-labels %w %w %w)" ($proof $theorem $label))
    (let $theorem-with-vars (replace-greeks-by-variables $theorem)
      (add-atom &labels (Label $proof $theorem-with-vars $label)))))

;; Process the axiom of given index, that is insert the axiom into
;; pc-ab and return the next index.
;; NEXT: re-enable when fixed
;; (: process-axiom (-> Number Assertion (Maybe Number)))
(= (process-axiom $idx (MkAxiom $label $axiom))
   (progn
    (logger-infof "Iteration %w: add axiom %w" ($idx $label))
    (add-to-kbs $label $axiom)
    (Maybe.return (+ $idx 1))))

;; ECAN-guided rediscovery of proof(s) of a theorem.  It searches the
;; attention-focused rule base (&pc-rb-af, rebuilt from the current
;; attentional focus) FIRST; on a miss it falls back to the full &pc-rb.
;; Each tier is wrapped in `collapse` so a miss yields () (a value)
;; rather than a hard Prolog failure -- and each obc call is the only
;; one inside its own collapse.
(= (rediscover-proofs-ecan $idx $label $bound $proof $thrm)
   (if (ecan-use-agents)
  (rediscover-proofs-focused $idx $label $bound $proof $thrm)
       ;; Switch off: the base experiment's single search over the full rule
       ;; base, with no focus rebuilt and no tier logged.
       (let $proof-wo-bdy (replace-body-by-variable $proof)
         (collapse
          (if (search-all-proofs)
              (obc &pc-rb &pc-ab callback $bound (: $proof-wo-bdy $thrm))
              (once (obc &pc-rb &pc-ab callback $bound (: $proof-wo-bdy $thrm))))))))

(= (rediscover-proofs-focused $idx $label $bound $proof $thrm)
   (let $proof-wo-bdy (replace-body-by-variable $proof)
     ;; Rebuild the focused rule base from the current attentional focus.
     (let $_ (catch (union-rebuild-focused-rb $idx $label $thrm))
       (let $timed-result
           (timed_obc_tiers_once &pc-rb-af &pc-rb &pc-ab callback $bound
                                 (: $proof-wo-bdy $thrm)
                                 (theorem-timeout-seconds))
         (case $timed-result
           (((focused (: $p $t) $focus-seconds)
             (progn
              (logger-infof "  [tier] focused=%w full=%w af-hit=true"
                            ((size-atom (collapse (match &pc-rb-af (: $la $ta) $la)))
                             (size-atom (collapse (match &pc-rb (: $lb $tb) $lb)))))
              (logger-infof "  [timing] focus-seconds=%w fallback-seconds=0.0 timeout=none"
                            ($focus-seconds))
              (list (: $p $t))))
            ((fallback (: $p $t) $focus-seconds $total-seconds)
             (progn
              (logger-infof "  [tier] focused=%w full=%w af-hit=false"
                            ((size-atom (collapse (match &pc-rb-af (: $la $ta) $la)))
                             (size-atom (collapse (match &pc-rb (: $lb $tb) $lb)))))
              (logger-infof "  [timing] focus-seconds=%w fallback-seconds=%w timeout=none"
                            ($focus-seconds (- $total-seconds $focus-seconds)))
              (list (: $p $t))))
            ((not_found $focus-seconds $total-seconds)
             (progn
              (logger-infof "  [tier] focused=%w full=%w af-hit=false"
                            ((size-atom (collapse (match &pc-rb-af (: $la $ta) $la)))
                             (size-atom (collapse (match &pc-rb (: $lb $tb) $lb)))))
              (logger-infof "  [timing] focus-seconds=%w fallback-seconds=%w timeout=none"
                            ($focus-seconds (- $total-seconds $focus-seconds)))
              ()))
            ((timeout focused $focus-seconds $total-seconds)
             (progn
              (logger-infof "  [tier] focused=%w full=%w af-hit=false"
                            ((size-atom (collapse (match &pc-rb-af (: $la $ta) $la)))
                             (size-atom (collapse (match &pc-rb (: $lb $tb) $lb)))))
              (logger-infof "  [timing] focus-seconds=%w fallback-seconds=0.0 timeout=focused"
                            ($total-seconds))
              (logger-infof "Search timed out after %ws in focused tier"
                            ((theorem-timeout-seconds)))
              SearchTimeout))
            ((timeout fallback $focus-seconds $total-seconds)
             (progn
              (logger-infof "  [tier] focused=%w full=%w af-hit=false"
                            ((size-atom (collapse (match &pc-rb-af (: $la $ta) $la)))
                             (size-atom (collapse (match &pc-rb (: $lb $tb) $lb)))))
              (logger-infof "  [timing] focus-seconds=%w fallback-seconds=%w timeout=fallback"
                            ($focus-seconds (- $total-seconds $focus-seconds)))
              (logger-infof "Search timed out after %ws in fallback tier"
                            ((theorem-timeout-seconds)))
              SearchTimeout))))))))

;; Process the theorem of a given index by rediscovering its proof, if
;; it succeeds then insert its alongside its proof(s) into the
;; propositional calculus knowledge bases and return the next idx, or
;; Nothing if it fails.
;;
;; NEXT: re-enable when fixed
;; (: process-theorem-search (-> Number Number Assertion (Maybe Number)))
(= (process-theorem-search $idx $bound (MkTheorem $label $proof $thrm))
   (progn
    (logger-infof "Iteration %w: %w-guided search proof of %w up to size %w"
            ($idx (selector-mode) $label $bound))
    (let $prfs-thrms (rediscover-proofs-ecan $idx $label $bound $proof $thrm)
      (if (== $prfs-thrms SearchTimeout)
          ;; Keep later candidate sets identical across modes.  The theorem
          ;; statement becomes available, but its proof does not stimulate
          ;; ECAN or contribute oracle proof-usage information.
          (progn
           (logger-info "Timed-out theorem skipped; continuing")
             (if (== (selector-mode) ecan)
               ()
               (py-call (william_rank.observe (repr ()))))
           (add-to-kbs $label $thrm)
           (Just (+ $idx 1)))
      (if (== $prfs-thrms ())
          ;; No proof
          (progn (logger-info "No proof found")
                 Nothing)
          ;; One or more proofs
          (progn
           ;; For each proof: map proof to label, stimulate the labels it
           ;; uses, and create/strengthen Hebbian links between every pair
           ;; of co-used labels (so future diffusion pre-activates them
           ;; together).
           (collapse
            (let (: $p $t) (superpose $prfs-thrms)
                 (progn
                  (logger-infof "Found proof%w %w" (: $p))
                  (add-to-labels $p $t $label)
                    (if (== (selector-mode) ecan)
                      ()
                      (py-call (william_rank.observe
                          (repr (ecan-proof-kb-labels $p)))))
                  (if (ecan-use-agents)
                      (progn
                       (ecan-stimulate-proof $p)
                       (ecan-update-hebbian-links (ecan-proof-kb-labels $p)))
                      ()))))
           ;; Add proved theorem as lemma in kbs
           (add-to-kbs $label $thrm)
           ;; Run ECAN agents (diffusion + rent).  Skipped when the daemon is
           ;; running them continuously on its own thread.
           (if (ecan-background) () (ecan-run-agents))
           ;; Output next index
           (Just (+ $idx 1))))))))

;; Process the theorem of a given index, that is either check or
;; rediscover its proof, if it succeeds then insert it alongside its
;; proof into the propositional calculus knowledge bases and return
;; the next idx, or Nothing if it fails.
;; NEXT: re-enable when fixed
;; (: process-theorem (-> Number Assertion (Maybe Number)))
(= (process-theorem $idx (MkTheorem $label $proof $thrm))
   (let $bound (term-size $proof)
     (process-theorem-search $idx $bound (MkTheorem $label $proof $thrm))))

;; Process the assertion corresponding to the given index and return
;; the index of the next assertion to process.  Meaning, if the
;; assertion is an axiom, insert the axiom in the knowledge base, and
;; if the assertion is a theorem, verify or proof the theorem and then
;; insert it in the knowledge base as if it were an axiom.  If it
;; fails to verify or proof then return Nothing instead of the next
;; index.
;; (: process-assertion (-> Number (Maybe Number)))
(= (process-assertion $idx)
   (progn
    (logger-tracef "Call: (process-assertion %w)" ($idx))
    (case (match &pc-idxd (MkIndexed $idx $asrt) $asrt)
      (((MkAxiom $label $axiom) (process-axiom $idx $asrt))
       ((MkTheorem $label $proof $thrm) (process-theorem $idx $asrt))
       ($else Nothing)))))

;; Like process-assertion but wrapped in Maybe.bind to accept maybe a
;; number, which the until construct needs.
;; (: process-assertion-m (-> (Maybe Number) (Maybe Number)))
(= (process-assertion-m $midx) (Maybe.bind $midx process-assertion))

;;;;;;;;;;;;;;;;;;;;;;;
;; Process PC Corpus ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; Loop over all assertions of the corpus
;; MUST be wrapped in once.  !(...) compiles to findall, which enumerates ALL
;; solutions of the goal, so any failure inside the recursion sends Prolog
;; backtracking into whatever choice points earlier iterations left open and
;; REPLAYS them -- re-running add-to-kbs, which is why the rule base keeps
;; growing across replays (full=135, 136, 137 ... in the tier log).
;;
;; OBSERVED without it (run of 2026-08-18, up-to-idx 182): iteration 158 (jc,
;; size 7) missed the focused tier at 10:24:51, spent 56 minutes in the
;; full-KB search, and then the whole loop restarted from Iteration 2 at
;; 11:21:00.  Three complete passes in one log; the run never terminated.
;; An ordinary miss is NOT the trigger -- that path returns Nothing and stops
;; cleanly (verified separately by forcing an unprovable bound).
;;
;; once commits to the first solution of the loop, which bounds the DAMAGE,
;; not the cause: a theorem the search cannot crack still costs its full wall
;; clock.  The LLM variant solves that separately, with obc-timeout-seconds /
;; timed_obc_once.
;;
;; AND IT DOES NOT FULLY PREVENT THE REPLAY.  Measured on the run of
;; 2026-08-18 16:03 (up-to-idx 182), with this once already in place: the
;; loop still made two complete passes, the second starting at 16:21:29
;; immediately after iteration 181 took 10m13s.  So treat this as mitigation
;; and check the log for a second `Iteration 6:' before trusting a run's
;; timings -- grep -c 'Iteration 6:' should be 1.
!(if (and (ecan-use-agents) (ecan-background))
     (progn (add-atom &ecan-ctl (running True))
            (translatePredicate (ecan_bg_start $bg-ok)))
     ())
!(once (until equal-to-upidx-or-nothing process-assertion-m (Just 2)))
!(if (and (ecan-use-agents) (ecan-background))
     (progn (ecan-daemon-stop)
            (logger-infof "[bg] daemon sweeps=%w final-funds=%w"
                          ((size-atom (collapse (match &ecan-ctl (tick) 1)))
                           (getAttentionParam FUNDS_STI))))
     ())

;; Log the content of pc-rb and pc-ab
!(logger-debugf "pc-rb: %w" ((get-atoms &pc-rb)))
!(logger-debugf "pc-ab: %w" ((get-atoms &pc-ab)))
