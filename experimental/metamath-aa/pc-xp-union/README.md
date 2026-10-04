# ECAN/WILLIAM cascade benchmark

This benchmark tests whether WILLIAM can improve Hyperon proof search by
reordering ECAN's selected premises. Both modes receive ECAN's unchanged
top-$k$ candidate set and the same 300-second theorem deadline:

- `ecan` searches candidates in ECAN order.
- `union` searches the same candidates in WILLIAM model03 order. The legacy
  mode name is retained for command-line compatibility.

## Result

One sequential run searched 177 Metamath propositional-calculus theorems:

| Selector | Proofs | Timeouts | Total search time | Solved search time |
| --- | ---: | ---: | ---: | ---: |
| ECAN | 176 | 1 | 353.388 s | 53.387 s |
| ECAN -> WILLIAM cascade | 176 | 1 | 329.422 s | **29.420 s** |

Both modes timed out on the same final theorem, `pm2.61iii`, after 300 seconds.
`Solved search time` excludes that common timeout and sums only attempts that
produced proofs. On those attempts the cascade used 44.9% less search time;
ECAN took 1.81 times as long. Including the timeout, the reduction was 6.8%.

Search time is logged Prolog proof-search time. It excludes WILLIAM scoring,
Python IPC, logging, startup, and orchestration overhead.

## Tested revisions

- Python 3.12.3 and SWI-Prolog 10.1.16
- William 0.2.4
- PeTTa `ae66fa8e41dcd5539d614706bd4e5cfb34f9608d`
- infcontrol `648f26d5b64cda9a4f9fee88077cf408a0ee3ea1`
- chaining benchmark tag `william-cascade-benchmark-v1`
- metta-attention `5c6e71cf1488b13504199d4687f3fe840f67445f`
- petta_lib_logger `4601951eb84cbec9ac9966974f3b87d0849c16e4`

Create the complete tested checkout from an empty directory:

```bash
mkdir hyperon-benchmark
cd hyperon-benchmark

git clone https://github.com/trueagi-io/PeTTa.git
git -C PeTTa checkout ae66fa8e41dcd5539d614706bd4e5cfb34f9608d

git clone https://github.com/af271/infcontrol.git
git -C infcontrol checkout 648f26d5b64cda9a4f9fee88077cf408a0ee3ea1

git clone --branch william-cascade-benchmark-v1 \
  https://github.com/af271/chaining.git chaining-pc-xp-benchmark

git clone https://github.com/Bitseat/metta-attention.git \
  chaining-pc-xp-benchmark/metta-attention
git -C chaining-pc-xp-benchmark/metta-attention checkout \
  5c6e71cf1488b13504199d4687f3fe840f67445f
```

Create the Python environment:

```bash
python3 -m venv infcontrol/.venv
infcontrol/.venv/bin/python -m pip install --upgrade pip
infcontrol/.venv/bin/python -m pip install -e './infcontrol[dev,william]'
```

The checked-in `infcontrol/models/model03` is sufficient for inference. PeTTa
downloads the pinned logger dependency on first execution, which requires
network access.

## Reproduce

From the common parent directory:

```bash
ROOT="$PWD"
export PETTA_RUNNER="$ROOT/PeTTa/run.sh"
export WILLIAM_PYTHON="$ROOT/infcontrol/.venv/bin/python"
export INFCONTROL_MODEL_DIR="$ROOT/infcontrol/models/model03"
BENCHMARK_DIR="$ROOT/chaining-pc-xp-benchmark/experimental/metamath-aa/pc-xp-union"

"$WILLIAM_PYTHON" -m pytest -q "$ROOT/infcontrol/tests"

cd "$BENCHMARK_DIR"
python3 run_benchmark.py \
  --modes ecan union \
  --repeat 1 \
  --run-label timeout300 \
  --up-to-index 183 \
  --theorem-timeout 300 \
  --petta-runner "$PETTA_RUNNER"

"$WILLIAM_PYTHON" summarize_benchmark.py \
  --modes ecan union \
  --run-label timeout300 \
  --repeat 1
```

The summary reports `search_seconds`, including timeouts, and
`solved_seconds`, which includes only proof-producing attempts. Logs are named
`pc-xp-{mode}-timeout300-run-1.log` and are ignored by Git.

Do not run the modes concurrently: ECAN uses a background daemon, and parallel
runs would introduce avoidable machine contention.

## Fairness and limitations

For each theorem, ECAN selects the complete top-$k$ candidate set. Cascade mode
only changes its order; missing WILLIAM scores are appended in ECAN order. Both
modes search the focused rule base first and then the full rule base with the
remaining portion of the same deadline:

$$
t_{focused} + t_{fallback} \leq 300\text{ seconds}.
$$

Candidates and WILLIAM context are chronological. A theorem becomes available
only after its turn, and proof labels update the model only after search. A
timeout adds the theorem statement but not its known proof usage.

This is a development benchmark, not held-out evidence: model03 and the
cascade were developed on the same PC-XP corpus. The reported 300-second result
is one run and remains sensitive to machine load and ECAN's concurrent daemon.
It demonstrates a reproducible result on this workload, not universal
superiority or statistical significance.
