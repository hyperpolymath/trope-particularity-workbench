#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Consistency gate (the workbench `just check`): the NINE effects must agree across
# the vocabulary, the trainer, the map, and the README (EFFECT_COUNT=nine).
# Pure bash; no Python.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="\033[32m"; R="\033[31m"; O="\033[0m"
fail=0
EFFECTS=(p-preserving p-projecting p-collapsing p-detaching p-attenuating p-falsifying p-misbinding p-conflating p-fusing)
DECEPTIVE=(p-falsifying p-misbinding p-conflating)

[ "${#EFFECTS[@]}" -eq 9 ] || { echo -e "${R}FAIL${O} EFFECT_COUNT is ${#EFFECTS[@]}, expected 9"; fail=1; }

# vocabulary: one entry per effect, no extras
for e in "${EFFECTS[@]}"; do
  [ -f "$ROOT/vocabulary/$e.adoc" ] || { echo -e "${R}FAIL${O} missing vocabulary/$e.adoc"; fail=1; }
done
for f in "$ROOT"/vocabulary/p-*.adoc; do
  b=$(basename "$f" .adoc); found=0
  for e in "${EFFECTS[@]}"; do [ "$e" = "$b" ] && found=1; done
  [ "$found" = 1 ] || { echo -e "${R}FAIL${O} unexpected vocabulary entry: $b"; fail=1; }
done

# trainer: every effect key present + intro says nine
T="$ROOT/assets/particularity-trainer.html"
for e in "${EFFECTS[@]}"; do
  k="${e#p-}"
  grep -q "key:\"$k\"" "$T" || { echo -e "${R}FAIL${O} trainer.html missing key:\"$k\""; fail=1; }
done
grep -q "nine p-effects" "$T" || { echo -e "${R}FAIL${O} trainer.html intro not 'nine p-effects'"; fail=1; }

# map: every effect + the deceptive trio present
M="$ROOT/assets/trope-particularity-map.svg"
for e in "${EFFECTS[@]}"; do grep -q "$e" "$M" || { echo -e "${R}FAIL${O} map.svg missing $e"; fail=1; }; done
for d in "${DECEPTIVE[@]}"; do grep -q "$d" "$M" || { echo -e "${R}FAIL${O} map.svg deceptive group missing $d"; fail=1; }; done

# README: every effect + count + arity sentence
RM="$ROOT/README.adoc"
for e in "${EFFECTS[@]}"; do grep -q "\`$e\`" "$RM" || { echo -e "${R}FAIL${O} README missing \`$e\`"; fail=1; }; done
grep -q "nine terms" "$RM" || { echo -e "${R}FAIL${O} README not 'nine terms'"; fail=1; }
grep -q "seven single-instance" "$RM" || { echo -e "${R}FAIL${O} README arity sentence missing"; fail=1; }

if [ "$fail" = 0 ]; then
  echo -e "${G}vocabulary-check${O}: nine effects consistent across vocabulary/ (9), trainer, map, README (deceptive: ${DECEPTIVE[*]})"
else echo -e "${R}vocabulary-check: problems${O}"; fi
exit "$fail"
