#!/usr/bin/env python3
"""Run equal-budget ECAN, WILLIAM, and union proof-search variants."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
SOURCE = HERE / "pc-xp-union.metta"


def _replace_once(source: str, pattern: str, replacement: str) -> str:
    result, count = re.subn(pattern, replacement, source, count=1)
    if count != 1:
        raise ValueError(f"expected one match for {pattern!r}, found {count}")
    return result


def render_variant(
    mode: str, up_to_index: int, theorem_timeout: float, log_name: str
) -> str:
    source = SOURCE.read_text(encoding="utf-8")
    source = _replace_once(
        source,
        r"\(= \(selector-mode\) (?:ecan|william|union)\)",
        f"(= (selector-mode) {mode})",
    )
    source = _replace_once(
        source,
        r"\(= \(up-to-idx\) \d+\)",
        f"(= (up-to-idx) {up_to_index})",
    )
    source = _replace_once(
        source,
        r"\(= \(theorem-timeout-seconds\) [\d.]+\)",
        f"(= (theorem-timeout-seconds) {theorem_timeout})",
    )
    return _replace_once(
        source,
        r'\(= \(log-filepath\) "[^"]+"\)',
        f'(= (log-filepath) "{log_name}")',
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--modes", nargs="+", choices=("ecan", "william", "union"),
        default=("ecan", "william", "union"),
    )
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--run-label", default="")
    parser.add_argument("--up-to-index", type=int, default=183)
    parser.add_argument("--theorem-timeout", type=float, default=60.0)
    parser.add_argument("--petta-runner", default=os.environ.get("PETTA_RUNNER"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.dry_run and not args.petta_runner:
        parser.error("pass --petta-runner or set PETTA_RUNNER to PeTTa/run.sh")

    for repeat in range(1, args.repeat + 1):
        for mode in args.modes:
            label = f"-{args.run_label}" if args.run_label else ""
            stem = f"pc-xp-{mode}{label}-run-{repeat}"
            generated = HERE / f".{stem}.metta"
            log_path = HERE / f"{stem}.log"
            variant = render_variant(
                mode, args.up_to_index, args.theorem_timeout, log_path.name
            )
            if args.dry_run:
                print(f"would run {mode} repeat {repeat}: {log_path}")
                continue
            generated.write_text(variant, encoding="utf-8")
            log_path.unlink(missing_ok=True)
            print(f"running {mode} repeat {repeat}: {log_path}", flush=True)
            try:
                subprocess.run(
                    ["sh", args.petta_runner, str(generated), "--silent"],
                    cwd=HERE,
                    check=True,
                )
            finally:
                generated.unlink(missing_ok=True)


if __name__ == "__main__":
    main()