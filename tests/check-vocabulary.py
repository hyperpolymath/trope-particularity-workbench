#!/usr/bin/env python3
# SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
# SPDX-License-Identifier: MPL-2.0
"""Consistency gate (the workbench `just check`): the NINE effects must agree
across the vocabulary, the trainer, the map, and the README (EFFECT_COUNT=nine).
No network, pure text checks."""
from __future__ import annotations
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GREEN, RED, OFF = "\033[32m", "\033[31m", "\033[0m"

EFFECTS = ["p-preserving", "p-projecting", "p-collapsing", "p-detaching",
           "p-attenuating", "p-falsifying", "p-misbinding", "p-conflating", "p-fusing"]
DECEPTIVE = {"p-falsifying", "p-misbinding", "p-conflating"}


def main() -> int:
    fails = []
    n = len(EFFECTS)
    if n != 9:
        fails.append(f"EFFECT_COUNT is {n}, expected 9")

    voc = ROOT / "vocabulary"
    for e in EFFECTS:
        if not (voc / f"{e}.adoc").exists():
            fails.append(f"missing vocabulary/{e}.adoc")
    extra = {p.stem for p in voc.glob("p-*.adoc")} - set(EFFECTS)
    if extra:
        fails.append(f"unexpected vocabulary entries: {sorted(extra)}")

    trainer = (ROOT / "assets" / "particularity-trainer.html").read_text(encoding="utf-8")
    for e in EFFECTS:
        key = e[2:]  # strip "p-"
        if f'key:"{key}"' not in trainer:
            fails.append(f"trainer.html missing effect key:\"{key}\"")
    if "nine p-effects" not in trainer:
        fails.append("trainer.html intro does not say 'nine p-effects'")

    mp = (ROOT / "assets" / "trope-particularity-map.svg").read_text(encoding="utf-8")
    for e in EFFECTS:
        if e not in mp:
            fails.append(f"map.svg missing {e}")
    for d in DECEPTIVE:
        if d not in mp:
            fails.append(f"map.svg deceptive group missing {d}")

    readme = (ROOT / "README.adoc").read_text(encoding="utf-8")
    for e in EFFECTS:
        if f"`{e}`" not in readme:
            fails.append(f"README missing `{e}`")
    if "nine terms" not in readme or "seven single-instance" not in readme:
        fails.append("README arity/count sentence not updated to nine")

    for e in EFFECTS:
        if e in fails:
            continue
    if fails:
        print(f"{RED}vocabulary-check: {len(fails)} problem(s){OFF}")
        for f in fails:
            print(f"  {RED}-{OFF} {f}")
        return 1
    print(f"{GREEN}vocabulary-check{OFF}: nine effects consistent across "
          f"vocabulary/ ({n}), trainer, map, README "
          f"(deceptive: {', '.join(sorted(DECEPTIVE))})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
