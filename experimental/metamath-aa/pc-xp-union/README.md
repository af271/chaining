# Equal-budget ECAN/WILLIAM benchmark

This checkout compares `ecan`, `william`, and `union` through the same proof
search and fallback path. At each theorem all modes receive the dynamic
`ecan-focus-size`; union alternates the complete rankings before deduplication
and truncation, so overlap cannot reduce its effective budget.

The experiment needs PeTTa, the infcontrol environment, and a trained model:

```bash
export PETTA_RUNNER=/path/to/PeTTa/run.sh
export WILLIAM_PYTHON=/home/arthur/workspace/hyperon/infcontrol/.venv/bin/python
export INFCONTROL_MODEL_DIR=/home/arthur/workspace/hyperon/infcontrol/models/model03

python3 run_benchmark.py --repeat 3 --run-label model03 --theorem-timeout 60
```

The timeout is one shared wall-clock budget per theorem: focused search uses
the first part, and full-KB fallback receives only the remaining time. This
prevents a hard theorem from blocking an entire run while keeping all three
selectors under the same limit. After a timeout, the theorem statement is
added so every mode sees the same later candidate set, but its known proof is
not used for stimulation or scoring. The default is 60 seconds.

For a quick integration check, stop after the first searched theorem:

```bash
python3 run_benchmark.py --modes union --up-to-index 7
```

Each run gets a fresh `pc-xp-MODE-run-N.log`. The log contains a `[ranking]`
record with theorem index, label, mode, budget, complete ECAN/WILLIAM rankings,
and selected labels. A `[timing]` record reports focused/fallback seconds and
the tier in which a timeout occurred. Parse a log with:

```bash
/home/arthur/workspace/hyperon/infcontrol/.venv/bin/python \
  -m infcontrol.search_log_benchmark pc-xp-union-model03-run-1.log
```

Use `--summary-only` for aggregate hit, fallback, and timing metrics. Compare
only matching theorem indices and report medians across repeated runs because
the background ECAN daemon is concurrent.