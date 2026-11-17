#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Re-run the vocarium survey experiments (docs/theory/formalisms/
# vocarium-survey.adoc) and compare each verdict with the one the note records.
#
# It needs two binaries this repository does not build:
#   VOC             vocarium's store engine      (vocarium: zig build)
#   TROPECHECK_BIN  the checker's Rust fast core (trope-checker: cargo build --release
#                                                 --manifest-path src/rust/Cargo.toml)
# Both are required. A missing binary fails; it does not skip.
#
# One expected result is a known defect, recorded as such: E1c line 2 is the
# false acceptance of trope-checker issue 125. When that issue is fixed this
# script fails on that line, and the note and this table change together.
# Exit 0 = every verdict as recorded, 1 = a difference, 2 = cannot run.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FX="$HERE/examples/survey"
: "${VOC:?set VOC to the voc binary}" "${TROPECHECK_BIN:?set TROPECHECK_BIN to tropecheck-rs}"
[ -x "$VOC" ] || { echo "VOC is not executable: $VOC"; exit 2; }
[ -x "$TROPECHECK_BIN" ] || { echo "TROPECHECK_BIN is not executable: $TROPECHECK_BIN"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0; n=0

# expect <store> <use-model> <trope> <verdict> [<witness> <coordinate>]
expect() {
  local store=$1 um=$2 trope=$3 want=$4 wit=${5:-} coord=${6:-} out got
  n=$((n+1))
  if ! "$VOC" invoke --store "$FX/$store" --use-model "$um" "$trope" > "$TMP/ir.json" 2> "$TMP/err"; then
    echo "FAIL $store: voc invoke $um $trope: $(head -1 "$TMP/err")"; fail=1; return
  fi
  out=$("$TROPECHECK_BIN" "$TMP/ir.json" 2>&1); got=${out%%$'\t'*}
  if [ "$got" != "$want" ]; then echo "FAIL $store: $trope under $um gave '$out', the note records $want"; fail=1; return; fi
  if [ -n "$wit" ] && ! { grep -q "witness=$wit" <<<"$out" && grep -q "coord=$coord" <<<"$out"; }; then
    echo "FAIL $store: $trope under $um gave '$out', the note records witness $wit at $coord"; fail=1; return
  fi
  echo "ok   $store: $trope under $um -> $want${wit:+ ($wit, $coord)}"
}

# E1: a non-interpretive pipeline, with and without the provenance metadata.
expect e1-palimpsest.jsonl carries-emotional-lineage t_ni_kept     p-insufficient e_ni_kept     fate.context
expect e1-palimpsest.jsonl provenance-intact         t_ni_kept     p-sufficient
expect e1-palimpsest.jsonl carries-emotional-lineage t_ni_stripped p-insufficient e_ni_stripped fate.context
expect e1-palimpsest.jsonl provenance-intact         t_ni_stripped p-insufficient e_ni_stripped fate.record
# E1c: consent scope. Line 2 is the defect of trope-checker issue 125.
expect e1c-consent-scope.jsonl needs-training-consent t_training      p-sufficient
expect e1c-consent-scope.jsonl needs-training-consent t_research_only p-sufficient
# E2: a renamed repository identity.
expect e2-chora-history.jsonl resolve-by-id   t_id_after_rename p-sufficient
expect e2-chora-history.jsonl follow-old-path t_id_after_rename p-insufficient e_rename fate.bearer
# E4: one cadastre row.
expect e4-cadastre-row.jsonl triage-queue            t_scan_row p-sufficient
expect e4-cadastre-row.jsonl describe-the-repository t_scan_row p-insufficient e_scan fate.quality

# E2, the gap: vocarium refuses a revocation record.
n=$((n+1))
printf '%s\n' '{"t":"trope","id":"t_x","quality":"q","bearer":"b","context":"c","record":"r"}' \
              '{"t":"revocation","id":"r1","target":"t_x","reason":"id retired"}' > "$TMP/rev.jsonl"
if "$VOC" ingest "$TMP/rev.jsonl" > /dev/null 2> "$TMP/err"; then
  echo "FAIL revocation: vocarium accepted a revocation record; the note records it as refused (M2)"; fail=1
elif grep -q 'revocation records are reserved' "$TMP/err"; then
  echo "ok   revocation: refused, reserved for M2"
else echo "FAIL revocation: refused for another reason: $(head -1 "$TMP/err")"; fail=1; fi

# E3, the gap: the IR voc emits carries no warrant and no descriptive text.
n=$((n+1))
"$VOC" invoke --store "$FX/e1-palimpsest.jsonl" --use-model provenance-intact t_ni_kept > "$TMP/ir.json"
if jq -e '[.edges[] | has("warrant_id")] | any' "$TMP/ir.json" >/dev/null || jq -e '[.nodes[] | has("quality")] | any' "$TMP/ir.json" >/dev/null; then
  echo "FAIL emit: the emitted IR now carries a warrant or node text; the note records that it does not"; fail=1
else echo "ok   emit: the emitted IR carries no warrant id and no node text"; fi

echo
[ "$n" -eq 12 ] || { echo "survey experiments: $n cases ran, 12 expected"; exit 1; }
[ "$fail" -eq 0 ] && echo "survey experiments: 12 of 12 as recorded" || { echo "survey experiments: a result differs from the note"; exit 1; }
