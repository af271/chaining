# Equal-budget ECAN/WILLIAM cascade benchmark

This experiment measures premise selection in a real sequential Hyperon/MeTTa
proof search. It compares three selectors over the bundled Metamath
propositional-calculus corpus:

- `ecan`: ranks available lemmas by ECAN attention.
- `william`: ranks them with the learned contextual `infcontrol` model03.
- `union`: keeps ECAN's complete top-$k$ candidate set and uses WILLIAM to
  reorder those candidates before proof search. The name is retained for
  command-line compatibility; this mode is a safe ranking cascade.

The benchmark asks whether WILLIAM can improve proof search by ordering ECAN's
selected premises when candidate membership, candidate count, and theorem
timeout are held constant.

## Tested environment

The reported result was produced on Linux with:

- Python 3.12.3 (the packages require Python 3.11 or newer)
- SWI-Prolog 10.1.16 (PeTTa documents 9.3.x or newer)
- William 0.2.4
- PeTTa commit `ae66fa8e41dcd5539d614706bd4e5cfb34f9608d`
- metta-attention commit `5c6e71cf1488b13504199d4687f3fe840f67445f`
- infcontrol commit `08ff5bbe45cd56f665c5efc259a1da1679743e20`
- petta_lib_logger commit `4601951eb84cbec9ac9966974f3b87d0849c16e4`

Other recent revisions may work, but these are the revisions actually tested.
PeTTa starts SWI-Prolog with an 8 GiB stack limit. A full nine-run benchmark
can take a substantial amount of time; every difficult theorem may consume its
full 60-second allowance.

## Repository layout

Keep the three main repositories as siblings and clone `metta-attention`
inside the chaining checkout:

```text
hyperon-benchmark/
  PeTTa/
  infcontrol/
  chaining-pc-xp-benchmark/
    metta-attention/
```

The MeTTa program uses this relative layout. The propositional-calculus corpus
is already tracked by the chaining repository. On first execution PeTTa also
downloads the pinned `petta_lib_logger` revision into `pc-xp-union/repos/`, so
the first run requires network access.

## Installation

Install Git, Python 3.11 or newer, and SWI-Prolog 9.3 or newer first. On a
Debian/Ubuntu system with a sufficiently recent SWI-Prolog package, the base
tools are typically installed with:

```bash
sudo apt-get update
sudo apt-get install -y git python3 python3-venv swi-prolog
```

Then create the checkout layout:

```bash
mkdir hyperon-benchmark
cd hyperon-benchmark

git clone https://github.com/trueagi-io/PeTTa.git
git clone https://gitlab.com/occam_ua/infcontrol.git
git clone https://github.com/trueagi-io/chaining.git chaining-pc-xp-benchmark
git clone https://github.com/Bitseat/metta-attention.git \
  chaining-pc-xp-benchmark/metta-attention

git -C PeTTa checkout ae66fa8e41dcd5539d614706bd4e5cfb34f9608d
git -C infcontrol checkout 08ff5bbe45cd56f665c5efc259a1da1679743e20
git -C chaining-pc-xp-benchmark/metta-attention checkout \
  5c6e71cf1488b13504199d4687f3fe840f67445f
```

Use the chaining revision or branch containing this directory and
`pc-xp-union.metta`; the benchmark commit may differ after documentation or
upstream integration changes.

Create one Python environment for `infcontrol` and the WILLIAM bridge:

```bash
python3 -m venv infcontrol/.venv
infcontrol/.venv/bin/python -m pip install --upgrade pip
infcontrol/.venv/bin/python -m pip install -e './infcontrol[dev,william]'
```

No MORK or FAISS build is required for this benchmark. The checked-in
`infcontrol/models/model03` directory is self-contained and can be used
without the original training CSV.

Verify the Python side:

```bash
infcontrol/.venv/bin/python -m pytest -q infcontrol/tests
```

The expected result for the documented revision is 35 passing tests.

## Environment

From the common `hyperon-benchmark` parent directory, define portable absolute
paths once:

```bash
ROOT="$PWD"
export PETTA_RUNNER="$ROOT/PeTTa/run.sh"
export WILLIAM_PYTHON="$ROOT/infcontrol/.venv/bin/python"
export INFCONTROL_MODEL_DIR="$ROOT/infcontrol/models/model03"
BENCHMARK_DIR="$ROOT/chaining-pc-xp-benchmark/experimental/metamath-aa/pc-xp-union"
```

`WILLIAM_PYTHON` must point to the interpreter in which `infcontrol` and
William are installed. `INFCONTROL_MODEL_DIR` may point to another compatible
saved model, but the reported numbers below use model03.

## The model under test

The checked-in model03 is not a language model. It is a compact logistic
premise ranker built by WILLIAM's symbolic feature search. It contains one
learned formula feature, which penalizes a goal/candidate pair when it shares
fewer than one operator, and these eight selected historical features:

- candidate age;
- prior candidate use count;
- a one-observation-smoothed use prior;
- log-odds of a five-observation-smoothed use prior;
- use count in the previous 1, 2, 10, and 20 theorems.

The model service scores the whole candidate pool in one request. It does not
update history while scoring. After proof search finishes, a separate
`observe` request records which exposed candidates were used. This ordering is
what makes the context strictly online and prevents the current proof label
from leaking into its own score.

Model03 was trained from the same PC-XP trace corpus used by this benchmark.
Training used reproducibly sampled theorem groups and chronological
train/validation/test partitions, but this 177-theorem benchmark block was not
reserved as an untouched evaluation set before model and cascade development.
The reported numbers are therefore development-benchmark results, not an
independent estimate of generalization.

## Preflight checks

First check the model bridge without starting the theorem benchmark:

```bash
WILLIAM_PYTHON="$WILLIAM_PYTHON" \
INFCONTROL_MODEL_DIR="$INFCONTROL_MODEL_DIR" \
python3 "$ROOT/chaining-pc-xp-benchmark/experimental/metamath-aa/pc-xp-william/william_rank.py" \
  --selftest
```

The test parses representative S-expressions, verifies Greek-variable
canonicalization, starts the persistent prediction service, loads model03, and
requests a batch of candidate probabilities. It should finish with `All good.`

Next verify variant generation without invoking PeTTa:

```bash
cd "$BENCHMARK_DIR"
python3 run_benchmark.py --dry-run --repeat 3 --run-label model03
```

This should list nine planned runs: three each for `ecan`, `william`, and
`union`.

Finally run one searched theorem as an integration check:

```bash
python3 run_benchmark.py \
  --modes union \
  --up-to-index 7 \
  --run-label smoke \
  --theorem-timeout 60 \
  --petta-runner "$PETTA_RUNNER"
```

This exercises PeTTa, the attention modules, SWI-Prolog worker threads, the
Python bridge, model loading, ranking, focused search, logging, and the online
observation message.

## Validation coverage

The 35-test Python suite covers the general infcontrol package as well as the
new benchmark path. In particular, focused tests verify that:

- context rows contain only information available before the current proof;
- the current theorem's labels do not affect their own features;
- the runtime tracker reproduces the early training-context values;
- a persistent `score -> observe -> score` sequence changes only later scores;
- pairwise training can move the required premise to rank one;
- non-improving or validation-harming features are rejected;
- repeated formula goals remain separate theorem instances;
- chronological theorem groups do not cross train, validation, and test
  boundaries;
- saved and reloaded models produce the same probabilities;
- complete, partial, focused-timeout, and fallback-timeout logs are parsed
  correctly.

The bridge self-test adds process-level coverage for S-expression parsing,
Greek-variable canonicalization, model discovery, process startup, and batched
prediction. The one-theorem smoke run adds an end-to-end check through PeTTa,
MeTTa imports, ECAN, SWI worker threads, WILLIAM, proof search, and log parsing.

## Running the full benchmark

Run all selectors sequentially three times:

```bash
cd "$BENCHMARK_DIR"
python3 run_benchmark.py \
  --modes ecan william union \
  --repeat 3 \
  --run-label model03 \
  --up-to-index 183 \
  --theorem-timeout 60 \
  --petta-runner "$PETTA_RUNNER"
```

On the tested machine, the complete nine-run benchmark took approximately 30
minutes. Actual duration varies with hardware, system load, and the number of
theorems that consume their full timeout.

The runner renders a temporary MeTTa variant for each mode and repetition,
executes it from `pc-xp-union`, and removes the generated source afterward.
Each run receives a fresh log named:

```text
pc-xp-ecan-model03-run-1.log
pc-xp-william-model03-run-1.log
pc-xp-union-model03-run-1.log
...
```

Logs are ignored by Git. Do not run multiple repetitions concurrently: ECAN
has a background daemon and concurrent runs would add machine contention to
the comparison.

## What the benchmark does

The corpus is processed chronologically. A theorem becomes available as a
candidate lemma only after its turn, so each selector sees the same growing
knowledge base.

For every theorem, the harness performs these steps:

1. Build ECAN's complete ranking from current short- and long-term importance.
2. For WILLIAM and union modes, send the goal, candidate formulas, and labels
   to one persistent model03 process.
3. Set the final focus budget to the dynamic `ecan-focus-size` for all modes.
4. Select ECAN's top candidates, WILLIAM's top candidates, or ECAN's exact
  top-$k$ set reordered by WILLIAM in cascade mode.
5. Search the focused rule base first.
6. If focused search misses, search the full rule base using only the remaining
   portion of the same 60-second wall-clock budget.
7. If a proof is found, stimulate ECAN with its used labels and send those
   labels to WILLIAM through `observe` for use by later theorems.
8. If a timeout occurs, add only the theorem statement to the later knowledge
   base. Do not use its known proof for ECAN stimulation or WILLIAM context.

The shared deadline enforces:

$$
t_{focused} + t_{fallback} \leq 60\text{ seconds}.
$$

The cascade cannot remove a premise selected by ECAN. It filters WILLIAM's
ranking to ECAN's top-$k$ set, preserves WILLIAM's order, and appends any
unscored labels in ECAN order. Consequently, an improvement measures the value
of WILLIAM's ordering without changing ECAN's candidate coverage or budget.

The model03 context is also chronological. Candidate features are computed
before the current proof is known. Only the subsequent `observe` request
updates candidate age, exposure, use counts, smoothed priors, recent-use
windows, and exponentially weighted usage history.

## Logged measurements

Every theorem records:

- theorem index, label, selector mode, and focus budget;
- complete ECAN and WILLIAM rankings and the final selected labels;
- focused and full rule-base sizes;
- whether focused search succeeded or fallback was needed;
- focused time, fallback time, and timeout tier;
- whether a proof was found.

A daemon summary marks a run as complete. The parser rejects mismatched
theorem/ranking records and keeps incomplete runs distinguishable from valid
measurements.

In the result table below, `Proofs found` is the number of theorem attempts
that returned a proof, `Timeouts` is the number terminated by the shared
deadline, and `Search time` is the sum of per-theorem search durations within
one run. It is calculated from the logged focused plus fallback Prolog search
times. WILLIAM scoring, Python IPC, logging, and orchestration overhead are not
included. Each displayed value is the median of the three complete runs for
that selector. Startup and installation time are also not included.

Inspect one run with:

```bash
"$WILLIAM_PYTHON" -m infcontrol.search_log_benchmark \
  pc-xp-union-model03-run-1.log --summary-only
```

Show every repetition per mode and aggregate median, mean, minimum, maximum,
and sample standard deviation:

```bash
"$WILLIAM_PYTHON" summarize_benchmark.py --run-label model03 --repeat 3
```

Use medians because the ECAN background daemon is concurrent and individual
wall-clock observations contain scheduler noise. Compare only runs with the
same theorem range, timeout, model, and focus policy.

## Reported results

For three sequential runs per mode, 177 searched theorems per run, model03,
the dynamic shared focus budget, and a 60-second shared theorem deadline, the
median results were:

| Selector | Proofs found | Timeouts | Search time |
| --- | ---: | ---: | ---: |
| ECAN | 176 | 1 | 100.859 s |
| WILLIAM model03 | 175 | 2 | 145.944 s |
| ECAN → WILLIAM cascade | **176** | **1** | **91.795 s** |

The cascade matched ECAN's proof count and timeout count in every repetition.
Its individual search times were 91.795, 87.456, and 92.180 seconds, compared
with ECAN's 100.859, 102.139, and 100.334 seconds. It therefore reduced median
search time by about 9.0% versus ECAN, with a 2.624-second sample standard
deviation. Direct WILLIAM top-$k$ selection was less stable and slower. When
ranking and bridge overhead are included, the cascade was faster in two of the
three repetitions, so the stable improvement claimed here is specifically in
proof-search time rather than end-to-end theorem latency.

The result does not come from WILLIAM adding or removing candidates: within
each cascade attempt, focused-rule membership is exactly the contemporaneous
ECAN top-$k$ set. Separately executed ECAN and cascade runs can still have
different ECAN rankings because the attention daemon is concurrent. The result
indicates that model03's learned structural and historical relevance can
improve search order after ECAN has supplied a coverage-safe candidate set.
The raw logs are generated artifacts and are not versioned; the commands above
recreate them and the parser checks that each measured run completed.

## Interpretation and limitations

This benchmark supports the following scoped claim:

> On the tested sequential Metamath-AA proof-search workload, using a
> leakage-free contextual WILLIAM model to reorder ECAN's unchanged top-$k$
> candidate set reduced median proof-search time under equal candidate and
> timeout budgets without reducing proof coverage in this development
> benchmark.

It does not establish universal superiority:

- The experiment covers one propositional-logic corpus and one theorem order.
- Model training, cascade design, and evaluation used the same PC-XP corpus.
  The cascade policy was chosen after inspecting this benchmark, so the result
  is not a held-out confirmation of either within-domain or cross-domain
  generalization.
- Three repetitions provide a useful median but not a strong statistical
  significance estimate.
- ECAN runs a concurrent background daemon, so timings remain sensitive to
  machine load and scheduler behavior.
- The reported search-time metric excludes model scoring and bridge overhead;
  end-to-end latency did not improve in every repetition.
- The benchmark compares complete selector systems. It does not isolate the
  contribution of each individual context feature.
- A timeout continues with the theorem statement but deliberately withholds
  its oracle proof usage. This preserves later candidate sets across modes but
  differs from a deployment that would stop at the first failed theorem.
- The checked-in model is reproducible for inference. Exact retraining also
  requires the original trace, which is not included because the generated
  context table is large.

The strongest follow-up is to freeze model03 and the cascade policy before
running them on an untouched theorem block or another Hyperon corpus. Further
experiments include more repetitions, additional theorem orders, feature
ablations, and confidence intervals over paired per-theorem timing and success
differences.