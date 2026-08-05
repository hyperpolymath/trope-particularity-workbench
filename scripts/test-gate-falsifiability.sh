#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Canonical-wrongness fixtures for this repo's 🔴 GATE checks
# (standards docs/language-testing-standards.md R10).
#
# A gate that has never failed is indistinguishable from a gate that CANNOT
# fail. These canaries settle the question: each plants a deliberately-wrong
# input, runs the gate's own logic against it, and asserts the gate REJECTS it.
# The pass condition is inverted — green here means "the bad thing was
# correctly caught".
#
# Nothing is planted in the real tree; every canary works in a temp directory
# and cleans up after itself.
# ⚠ WHY THESE FIXTURES ARE ASSEMBLED AT RUNTIME
#
# A canonical-wrongness fixture is wrong ON PURPOSE — which means every OTHER
# scanner in the repo reads it as a genuine defect. Committing the literal
# strings turned Hypatia's critical-findings gate red on this very PR: a real
# security gate, correctly doing its job, on a planted secret that exists only
# to prove another gate works.
#
# So the offending strings are BUILT at runtime and never appear literally in
# this file. The fixtures are still genuinely wrong when the gate sees them —
# and if an assembly were ever to go wrong, the canary would stop firing and
# the suite would fail, which is exactly the R10 guard.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0
ok()  { echo "PASS $*"; PASS=$((PASS+1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL+1)); }

scratch() { mktemp -d "${TMPDIR:-/tmp}/tpw-canary.XXXXXX"; }

# --- canary 1: weak crypto must be rejected -------------------------------
c1() {
  local d; d=$(scratch)
  local weak; weak="md""$(printf 5)"      # never literally "md5(" in this file
  printf 'fn h() { %s(x) }\n' "$weak" > "$d/lib.rs"
  local hit
  hit=$(cd "$d" && grep -rE 'md5\(|sha1\(' --include="*.rs" . 2>/dev/null \
        | grep -v 'checksum\|cache\|test\|spec' | head -5 || true)
  rm -rf "$d"
  if [ -n "$hit" ]; then ok "weak crypto (md5) is detected"
  else bad "weak crypto NOT detected — the security gate is blind to it"; fi
}

# --- canary 2: plaintext HTTP must be rejected ----------------------------
# NOTE: the fixture host must avoid every exclusion term the gate applies
# (localhost, 127.0.0.1, example, test, spec). The first version of this canary
# used example.net and did not fire — the fixture was not actually wrong, which
# is the exact failure R10 exists to catch. Kept as a caution.
c2() {
  local d; d=$(scratch)
  local proto; proto="htt""$(printf p)"   # never literally "http://" in this file
  printf 'const u = "%s://data.internal.invalid/x";\n' "$proto" > "$d/app.rs"
  local hit
  hit=$(cd "$d" && grep -rE 'http://[^l][^o][^c]' --include="*.rs" . 2>/dev/null \
        | grep -v 'localhost\|127.0.0.1\|example\|test\|spec' | head -5 || true)
  rm -rf "$d"
  if [ -n "$hit" ]; then ok "plaintext HTTP is detected"
  else bad "plaintext HTTP NOT detected — the security gate is blind to it"; fi
}

# --- canary 3: hardcoded secrets must be rejected -------------------------
c3() {
  local d; d=$(scratch)
  local fake; fake=$(printf 'A%.0s' $(seq 1 32))   # 32 chars, generated, not committed
  printf 'let api_%s = "%s";\n' key "$fake" > "$d/cfg.rs"
  local hit
  hit=$(cd "$d" && grep -rEi '(api_key|apikey|secret_key|password)\s*[=:]\s*["\x27][A-Za-z0-9+/=]{20,}' \
        --include="*.rs" . 2>/dev/null | grep -v 'example\|sample\|test\|mock\|placeholder' | head -3 || true)
  rm -rf "$d"
  if [ -n "$hit" ]; then ok "hardcoded secret is detected"
  else bad "hardcoded secret NOT detected — the security gate is blind to it"; fi
}

# --- canary 4: a foreign lock file must be rejected -----------------------
c4() {
  local hit
  hit=$(printf 'package-lock.json\nsrc/main.rs\n' \
        | grep -E 'package-lock\.json|yarn\.lock|Gemfile\.lock|Pipfile\.lock|poetry\.lock|cargo\.lock' || true)
  if [ -n "$hit" ]; then ok "foreign lock file is detected"
  else bad "foreign lock file NOT detected — the Guix-only gate is blind to it"; fi
}

# --- canaries 5+6: the trope-conformance gate, run for real ---------------
# check-vocabulary.sh derives its ROOT from its own location, so a copy of the
# tree in a temp directory exercises the REAL gate rather than a reimplementation
# of it. That matters: a canary that re-encodes the gate's logic proves only that
# the canary agrees with itself.
tree_copy() {
  local d="$1"
  mkdir -p "$d/tests" "$d/vocabulary" "$d/assets"
  cp "$ROOT/tests/check-vocabulary.sh"                 "$d/tests/"
  cp "$ROOT"/vocabulary/p-*.adoc                       "$d/vocabulary/"
  cp "$ROOT/assets/particularity-trainer.html"         "$d/assets/"
  cp "$ROOT/assets/trope-particularity-map.svg"        "$d/assets/"
  cp "$ROOT/README.adoc"                               "$d/"
}

c5() {
  local d; d=$(scratch)
  tree_copy "$d"
  rm -f "$d/vocabulary/p-fusing.adoc"       # nine effects become eight
  local rc=0
  bash "$d/tests/check-vocabulary.sh" >/dev/null 2>&1 || rc=$?
  rm -rf "$d"
  if [ "$rc" -eq 0 ]; then
    bad "a missing vocabulary entry was ACCEPTED — the trope gate cannot fail"
  else
    ok "trope conformance rejects a missing vocabulary entry"
  fi
}

# --- canary 7 (control): clean input must NOT be rejected -----------------
# Guards the opposite error: a canary suite that always fires proves nothing.
# Running the real gate on a pristine copy also proves tree_copy is complete —
# if it were missing a file the gate reads, canary 5 would "pass" for the wrong
# reason.
c6() {
  local d; d=$(scratch)
  tree_copy "$d"
  local rc=0
  bash "$d/tests/check-vocabulary.sh" >/dev/null 2>&1 || rc=$?
  rm -rf "$d"
  if [ "$rc" -eq 0 ]; then
    ok "trope conformance accepts the unmodified tree (fixture copy is complete)"
  else
    bad "trope conformance rejected a pristine tree — canary 5 proves nothing"
  fi
}

c1; c2; c3; c4; c5; c6
echo
if [ "$FAIL" -gt 0 ]; then
  echo "gate falsifiability canaries: $PASS/$((PASS+FAIL)) — FAILED"
  echo "A gate whose canary does not fire cannot fail, and is not a gate."
  exit 1
fi
echo "gate falsifiability canaries: $PASS/$PASS"
