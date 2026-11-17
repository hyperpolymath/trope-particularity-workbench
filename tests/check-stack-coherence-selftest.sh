#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# The stack coherence gate can fail: one planted disagreement per check.
#
# tests/check-stack-coherence.sh compares five repositories. This suite builds a
# small coherent stack in a scratch directory, shows the gate passes on it, then
# plants one disagreement at a time and requires the gate to fail on the check
# that owns it. Three controls show what must NOT fail: history kept in a
# changelog, a line that reports a claim as past, and a README citing documents
# its repository has. The coherent stack also holds a checker fixture at an older
# accepted IR version, which must pass.
#
# A gate whose canary does not fire cannot fail, and is not a gate.
# Exit 0 = every case behaved, 1 = a case did not.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$HERE/tests/check-stack-coherence.sh"
PASS=0; FAIL=0
ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PIN_A=$(printf 'a%.0s' $(seq 40)); PIN_B=$(printf 'b%.0s' $(seq 40))
SCAN_A=$(printf 'c%.0s' $(seq 40)); SCAN_B=$(printf 'd%.0s' $(seq 40))
MAP='Store/query track: haec → vocarium → hermeneia → trope-checker (verdict).'

# build <dir>: a coherent five-repository stack.
build() {
  local d=$1 r
  rm -rf "$d"; mkdir -p "$d"
  for r in trope-checker vocarium hermeneia haec trope-particularity-workbench; do
    mkdir -p "$d/$r/.github/workflows" "$d/$r/.machine_readable/6a2"
    printf '= %s\n\n%s\n' "$r" "$MAP" > "$d/$r/README.adoc"
    printf 'jobs:\n  scan:\n    uses: metadatastician/standards/.github/workflows/hypatia-scan-reusable.yml@%s\n' "$SCAN_A" \
      > "$d/$r/.github/workflows/hypatia-scan.yml"
    printf 'project = "%s"\ncoordination = "standards"\n' "$r" > "$d/$r/.machine_readable/6a2/ECOSYSTEM.a2ml"
  done
  mkdir -p "$d/trope-checker/schemas" "$d/trope-checker/tests" "$d/haec/design" "$d/vocarium/tests" "$d/hermeneia/docs"
  printf '{"properties":{"version":{"enum":["0.1","0.2"]}}}\n' > "$d/trope-checker/schemas/trope-ir.schema.json"
  cp "$d/trope-checker/schemas/trope-ir.schema.json" "$d/haec/design/trope-ir.schema.json"
  printf '{"version":"0.1"}\n' > "$d/trope-checker/tests/old-v0.1.ir.json"
  printf '{"version":"0.2"}\n' > "$d/vocarium/tests/slice.ir.json"
  printf 'TROPECHECK_PIN="%s"\n' "$PIN_A" > "$d/vocarium/tests/slice.sh"
  for r in hermeneia haec; do
    printf 'jobs:\n  t:\n    steps:\n      - uses: actions/checkout@v7.0.1\n        with:\n          repository: hyperpolymath/trope-checker\n          ref: %s\n          path: tc\n      - run: true\n' "$PIN_A" \
      > "$d/$r/.github/workflows/check.yml"
  done
  printf '= Notes\n\nThe adapter does not exist yet.\n' > "$d/hermeneia/docs/SPEC.adoc"
}

run() { STACK_ROOT="$1" bash "$GATE" > "$WORK/out" 2>&1; }

# expect_fail <check id> <label>: the gate must exit 1 and name that check.
expect_fail() {
  local id=$1 label=$2 rc
  run "$WORK/s"; rc=$?
  if [ "$rc" -eq 1 ] && grep -q "^FAIL $id " "$WORK/out"; then
    # Only the planted check may fail: a second failure means the fixture, not the gate, is at fault.
    if [ "$(grep -c '^FAIL ' "$WORK/out")" -eq 1 ]; then ok "$label"
    else bad "$label (other checks failed too: $(grep '^FAIL ' "$WORK/out" | cut -c6-8 | tr '\n' ' '))"; fi
  else bad "$label (exit $rc, no FAIL $id)"; sed 's/^/      /' "$WORK/out" | head -8; fi
}
expect_pass() {
  local label=$1 rc
  run "$WORK/s"; rc=$?
  if [ "$rc" -eq 0 ]; then ok "$label"; else bad "$label (exit $rc)"; grep '^FAIL' -A3 "$WORK/out" | sed 's/^/      /' | head -8; fi
}

echo "== the coherent stack =="
build "$WORK/s"; expect_pass "a coherent stack passes"
grep -q '^stack coherence: 10 checks, all agree$' "$WORK/out" && ok "all 10 checks ran" || bad "the pass did not report 10 checks"

echo "== one planted disagreement per check =="
build "$WORK/s"; rm -rf "$WORK/s/vocarium"
expect_fail S0 "S0 a missing repository fails (nothing read, nothing passes)"

build "$WORK/s"; printf '{"properties":{"version":{"enum":["0.1","0.2"]}},"x":1}\n' > "$WORK/s/haec/design/trope-ir.schema.json"
expect_fail S1 "S1 a vendored schema that differs from the checker's fails"

build "$WORK/s"; printf '{"version":"0.1"}\n' > "$WORK/s/vocarium/tests/slice.ir.json"
expect_fail S2 "S2 a producer emitting an older IR version fails"

build "$WORK/s"; printf '{"version":"0.9"}\n' > "$WORK/s/trope-checker/tests/old-v0.1.ir.json"
expect_fail S2 "S2 a checker fixture at a version the schema does not accept fails"

build "$WORK/s"; printf '= haec\n\nVocabulary track only.\n' > "$WORK/s/haec/README.adoc"
expect_fail S3 "S3 a README without the shared five-repo map fails"

build "$WORK/s"; printf '= Notes\n\nVocarium does not exist yet.\n' > "$WORK/s/hermeneia/docs/SPEC.adoc"
expect_fail S4 "S4 a retired claim asserted in a document fails"

build "$WORK/s"; sed -i "s/ref: $PIN_A/ref: $PIN_B/" "$WORK/s/haec/.github/workflows/check.yml"
expect_fail S5 "S5 two siblings on different checker commits fails"

build "$WORK/s"; sed -i '/ref: /d' "$WORK/s/hermeneia/.github/workflows/check.yml"
expect_fail S5 "S5 a sibling that tracks the checker's default branch fails"

build "$WORK/s"; sed -i "s/@$SCAN_A/@$SCAN_B/" "$WORK/s/hermeneia/.github/workflows/hypatia-scan.yml"
expect_fail S6 "S6 two revisions of the shared scan workflow fails"

build "$WORK/s"; printf '\nSee STATUS.adoc for the plan.\n' >> "$WORK/s/haec/README.adoc"
expect_fail S7 "S7 a README citing a root document the repository lacks fails"

build "$WORK/s"; printf 'project = "rsr-template-repo"\ncoordination = "standards"\n' > "$WORK/s/vocarium/.machine_readable/6a2/ECOSYSTEM.a2ml"
expect_fail S8 "S8 the mint template's identity in a repository's description fails"

build "$WORK/s"; printf 'kind = "{{PROJECT_KIND}}"\n' > "$WORK/s/haec/.machine_readable/6a2/ANCHOR.a2ml"
expect_fail S8 "S8 an unfilled template placeholder fails"

build "$WORK/s"; sed -i 's/coordination = "standards"/coordination = "vocarium"/' "$WORK/s/hermeneia/.machine_readable/6a2/ECOSYSTEM.a2ml"
expect_fail S9 "S9 two values for coordination fails"

echo "== what a narrower reading used to let through (review of #83) =="
# S4: a past-marker in ANOTHER clause does not make the claim historical.
build "$WORK/s"; printf '= Notes\n\nVocarium does not exist, so we no longer use its adapter.\n' > "$WORK/s/hermeneia/docs/SPEC.adoc"
expect_fail S4 "S4 a retired claim beside an unrelated 'no longer' clause fails"

# S5: a consumer with no recorded pin at all is not agreement.
build "$WORK/s"; rm "$WORK/s/haec/.github/workflows/check.yml"
expect_fail S5 "S5 a consumer that records no checker pin fails"

# S6: a caller on a branch name is outside any comparison of commits.
build "$WORK/s"; sed -i "s/@$SCAN_A/@main/" "$WORK/s/hermeneia/.github/workflows/hypatia-scan.yml"
expect_fail S6 "S6 a caller of the scan workflow on a branch name fails"

# --fetch lays the workbench out as a symlink; its files must still be read.
build "$WORK/s"; mv "$WORK/s/trope-particularity-workbench" "$WORK/wb-real"
ln -s "$WORK/wb-real" "$WORK/s/trope-particularity-workbench"
printf '= Notes\n\nVocarium does not exist yet.\n' > "$WORK/wb-real/NOTES.adoc"
expect_fail S4 "a disagreement inside a symlinked repository (the --fetch layout) fails"
rm -rf "$WORK/wb-real"

echo "== workflow spellings the first parser missed (second review of #83) =="
# A .yaml workflow is a workflow: a second checkout, scan caller or claim there counts.
build "$WORK/s"; sed "s/ref: $PIN_A/ref: $PIN_B/" "$WORK/s/haec/.github/workflows/check.yml" > "$WORK/s/haec/.github/workflows/extra.yaml"
expect_fail S5 "S5 a second checker commit in a .yaml workflow fails"

build "$WORK/s"; sed "s/@$SCAN_A/@$SCAN_B/" "$WORK/s/hermeneia/.github/workflows/hypatia-scan.yml" > "$WORK/s/hermeneia/.github/workflows/scan2.yaml"
expect_fail S6 "S6 a second scan revision in a .yaml workflow fails"

build "$WORK/s"; printf '# Vocarium does not exist yet.\nkey: value\n' > "$WORK/s/haec/config.yaml"
expect_fail S4 "S4 a retired claim in a .yaml file fails"

echo "== controls: what must not fail =="
build "$WORK/s"; printf '= Changelog\n\n* 2026-10: this used to read "Vocarium does not exist".\n* Vocarium does not exist (entry of 2026-07).\n' > "$WORK/s/hermeneia/CHANGELOG.adoc"
expect_pass "history kept in a changelog passes"

build "$WORK/s"; printf '= Notes\n\nThis line used to say Vocarium does not exist.\n' > "$WORK/s/hermeneia/docs/SPEC.adoc"
expect_pass "a line that reports the claim as past passes"

build "$WORK/s"; printf '\nSee README.adoc and CONTRIBUTING.adoc.\n' >> "$WORK/s/haec/README.adoc"; : > "$WORK/s/haec/CONTRIBUTING.adoc"
expect_pass "a README citing documents the repository has passes"

# YAML keys have no order and scalars may be quoted: the same pin, spelled otherwise.
build "$WORK/s"
printf 'jobs:\n  t:\n    steps:\n      - uses: actions/checkout@v7.0.1\n        with:\n          ref: %s\n          repository: hyperpolymath/trope-checker\n      - run: true\n' "$PIN_A" > "$WORK/s/haec/.github/workflows/check.yml"
expect_pass "a checkout with ref: above repository: passes"

build "$WORK/s"; sed -i "s/ref: $PIN_A/ref: \"$PIN_A\"/" "$WORK/s/haec/.github/workflows/check.yml"
sed -i "s/ref: $PIN_A/ref: '$PIN_A'  # pinned/" "$WORK/s/hermeneia/.github/workflows/check.yml"
expect_pass "quoted checker pins pass"

echo "== the register itself =="
build "$WORK/s"; printf '# only a comment\n' > "$WORK/empty.tsv"
STACK_ROOT="$WORK/s" STACK_CLAIMS="$WORK/empty.tsv" bash "$GATE" > "$WORK/out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q '^FAIL S4 ' "$WORK/out" && ok "an empty retired-claims register fails (nothing checked)" || bad "an empty register gave exit $rc"

echo
EXPECTED=28
[ "$((PASS+FAIL))" -eq "$EXPECTED" ] || { echo "stack coherence self-test: $((PASS+FAIL)) cases ran, $EXPECTED expected"; exit 1; }
echo "stack coherence self-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
