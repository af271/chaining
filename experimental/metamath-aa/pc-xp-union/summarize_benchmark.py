"""Report per-run and aggregate proof-search benchmark metrics."""

from __future__ import annotations

import argparse
from pathlib import Path
from statistics import mean, median, stdev

from infcontrol.search_log_benchmark import parse_search_log

HERE = Path(__file__).resolve().parent


def _theorem_seconds(theorem: dict) -> float:
    return theorem.get("focus_seconds", 0.0) + theorem.get("fallback_seconds", 0.0)


def _print_results(mode: str, runs: list[dict]) -> None:
    print(f"[{mode}]")
    print(
        f"{'run':<8} {'proofs':>10} {'timeouts':>10} "
        f"{'search_seconds':>16} {'solved_seconds':>16}"
    )
    for repetition, run in enumerate(runs, 1):
        solved_seconds = sum(
            _theorem_seconds(theorem)
            for theorem in run["theorems"]
            if theorem.get("result") == "proof"
        )
        print(
            f"{repetition:<8} {run['proofs_found']:>10} {run['timeouts']:>10} "
            f"{run['search_seconds_total']:>16.3f} {solved_seconds:>16.3f}"
        )

    metrics = {
        "proofs": [run["proofs_found"] for run in runs],
        "timeouts": [run["timeouts"] for run in runs],
        "search_seconds": [run["search_seconds_total"] for run in runs],
        "solved_seconds": [
            sum(
                _theorem_seconds(theorem)
                for theorem in run["theorems"]
                if theorem.get("result") == "proof"
            )
            for run in runs
        ],
    }
    summaries = (
        ("median", median),
        ("mean", mean),
        ("min", min),
        ("max", max),
        ("stdev", stdev if len(runs) > 1 else lambda values: 0.0),
    )
    print("summary")
    for name, summarize in summaries:
        print(
            f"{name:<8} {summarize(metrics['proofs']):>10.3f} "
            f"{summarize(metrics['timeouts']):>10.3f} "
            f"{summarize(metrics['search_seconds']):>16.3f} "
            f"{summarize(metrics['solved_seconds']):>16.3f}"
        )
    print()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--modes",
        nargs="+",
        choices=("ecan", "william", "union"),
        default=("ecan", "william", "union"),
    )
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--run-label", default="model03")
    parser.add_argument("--directory", type=Path, default=HERE)
    args = parser.parse_args()

    label = f"-{args.run_label}" if args.run_label else ""
    for mode in args.modes:
        runs = []
        for repetition in range(1, args.repeat + 1):
            path = args.directory / f"pc-xp-{mode}{label}-run-{repetition}.log"
            parsed = parse_search_log(path.read_text(encoding="utf-8"))
            if len(parsed) != 1 or not parsed[0]["complete"]:
                raise RuntimeError(f"incomplete or ambiguous run: {path}")
            runs.append(parsed[0])

        _print_results(mode, runs)


if __name__ == "__main__":
    main()