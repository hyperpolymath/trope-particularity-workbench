#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Stack coherence gate: the five trope-stack repositories must agree with each
# other about the facts they share.
#
# Each repository describes the others: which IR version is current, who feeds
# whom, which commit of the checker it builds against, whether a sibling exists.
# Nothing compared those descriptions. Measured 2026-11-17 on the five `main`
# branches: hermeneia said in three places that Vocarium does not exist while
# vocarium's store engine was built and gated; haec's design notes kept an
# ordering the calculus replaced in v0.2; two repositories still carried the
# mint template's identity; "coordination" had two values; and the shared scan
# workflow was pinned at two revisions.
#
# This gate reads, and never writes. It reads `.machine_readable/` too, which
# is where several of the disagreements live.
#
# Usage:
#   tests/check-stack-coherence.sh            siblings are ../<name>
#   STACK_ROOT=/dir tests/check-stack-coherence.sh
#   tests/check-stack-coherence.sh --fetch    clone the four siblings' default
#                                             branches into a scratch directory
#
# A sibling that is missing FAILS the gate: nothing read, nothing passes.
# Exit 0 = coherent, 1 = at least one disagreement, 2 = cannot run.
# Pure bash, jq, awk, sha256sum. No Python.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS=(trope-checker vocarium hermeneia haec trope-particularity-workbench)
OWNER="https://github.com/hyperpolymath"
CLAIMS="${STACK_CLAIMS:-$HERE/tests/stack-coherence/retired-claims.tsv}"

for t in jq awk sha256sum grep sed; do
  command -v "$t" >/dev/null || { echo "check-stack-coherence: $t is required"; exit 2; }
done
[ -f "$CLAIMS" ] || { echo "check-stack-coherence: no retired-claims register at $CLAIMS"; exit 2; }

SCRATCH=""
cleanup() { [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

if [ "${1:-}" = "--fetch" ]; then
  command -v git >/dev/null || { echo "check-stack-coherence: git is required for --fetch"; exit 2; }
  SCRATCH="$(mktemp -d)"
  STACK_ROOT="$SCRATCH"
  for r in "${REPOS[@]}"; do
    if [ "$r" = "trope-particularity-workbench" ]; then
      ln -s "$HERE" "$SCRATCH/$r"
    elif ! git clone -q --depth 1 "$OWNER/$r" "$SCRATCH/$r" 2>"$SCRATCH/clone.err"; then
      echo "check-stack-coherence: could not clone $r: $(head -1 "$SCRATCH/clone.err")"; exit 2
    fi
  done
else
  STACK_ROOT="${STACK_ROOT:-$(cd "$HERE/.." && pwd)}"
fi

FAILS=0
CHECKS=0
fail() { printf 'FAIL %s  %s\n' "$1" "$2"; shift 2; for l in "$@"; do printf '       %s\n' "$l"; done; FAILS=$((FAILS+1)); }
pass() { printf 'ok   %s  %s\n' "$1" "$2"; }
check() { CHECKS=$((CHECKS+1)); }

# --- S0: every repository is there ------------------------------------------
check
missing=()
for r in "${REPOS[@]}"; do [ -d "$STACK_ROOT/$r" ] || missing+=("$r"); done
if [ "${#missing[@]}" -gt 0 ]; then
  fail S0 "repositories not found under $STACK_ROOT" "${missing[@]}"
  echo; echo "stack coherence: cannot compare repositories that are not there"; exit 1
fi
pass S0 "all five repositories are present"

cd "$STACK_ROOT" || exit 2
SCHEMA="trope-checker/schemas/trope-ir.schema.json"

# Text files worth reading, per repository; never a build tree or a clone.
text_files() {
  find "$1" \( -name .git -o -name target -o -name node_modules -o -name _build -o -name .lake \
              -o -name zig-cache -o -name .zig-cache -o -name zig-out \) -prune -o -type f \
       \( -name '*.adoc' -o -name '*.md' -o -name '*.rs' -o -name '*.zig' -o -name '*.idr' \
          -o -name '*.sh' -o -name '*.yml' -o -name '*.a2ml' -o -name '*.deed' -o -name 'Justfile' \) -print
}

# --- S1: every vendored copy of the IR schema is the checker's --------------
check
if [ ! -f "$SCHEMA" ]; then
  fail S1 "the canonical schema is missing" "$SCHEMA"
else
  want=$(sha256sum "$SCHEMA" | cut -d' ' -f1); bad=()
  while IFS= read -r f; do
    [ "$f" = "./$SCHEMA" ] && continue
    got=$(sha256sum "$f" | cut -d' ' -f1)
    [ "$got" = "$want" ] || bad+=("$f sha256 $got" "$SCHEMA sha256 $want")
  done < <(find . -name .git -prune -o -name 'trope-ir.schema.json' -print)
  if [ "${#bad[@]}" -gt 0 ]; then fail S1 "a vendored IR schema differs from the checker's" "${bad[@]}"
  else pass S1 "vendored IR schemas match the checker's"; fi
fi

# --- S2: every IR document declares the current IR version ------------------
check
current=$(jq -r '.properties.version.enum | last // empty' "$SCHEMA" 2>/dev/null)
if [ -z "$current" ]; then
  fail S2 "cannot read the current IR version from the schema" "$SCHEMA: .properties.version.enum"
else
  # The checker keeps documents at older accepted versions on purpose (its
  # conformance suite proves they still grade). Every other repository is a
  # producer or a consumer of today's IR and must be at the current version.
  bad=(); n=0
  while IFS= read -r f; do
    n=$((n+1))
    v=$(jq -r '.version // "absent"' "$f" 2>/dev/null || echo unreadable)
    case "$f" in
      ./trope-checker/*)
        jq -e --arg v "$v" '.properties.version.enum | index($v) != null' "$SCHEMA" >/dev/null 2>&1 \
          || bad+=("$f declares version $v, which the schema does not accept") ;;
      *)
        [ "$v" = "$current" ] || bad+=("$f declares version $v; the schema's current version is $current") ;;
    esac
  done < <(find . -name .git -prune -o -name '*.ir.json' -print)
  if [ "$n" -eq 0 ]; then fail S2 "no IR document found in any repository (nothing read)"
  elif [ "${#bad[@]}" -gt 0 ]; then fail S2 "IR documents not at the current version" "${bad[@]}"
  else pass S2 "$n IR documents: producers and consumers at $current, the checker within the accepted set"; fi
fi

# --- S3: the shared five-repo map sentence is in every README ---------------
check
MAP='haec → vocarium → hermeneia → trope-checker'
bad=()
for r in "${REPOS[@]}"; do
  grep -qF "$MAP" "$r/README.adoc" 2>/dev/null || bad+=("$r/README.adoc does not carry: $MAP")
done
if [ "${#bad[@]}" -gt 0 ]; then fail S3 "the five-repo map is not the same in every README" "${bad[@]}"
else pass S3 "every README carries the same five-repo map"; fi

# --- S4: no repository still asserts a retired claim ------------------------
# The register is tests/stack-coherence/retired-claims.tsv:
#   id <TAB> extended regex <TAB> what superseded it <TAB> regex of paths allowed to keep it
check
bad=(); rows=0
while IFS=$'\t' read -r id re why allow; do
  case "$id" in ''|'#'*) continue ;; esac
  rows=$((rows+1))
  for r in "${REPOS[@]}"; do
    while IFS= read -r f; do
      [ -n "$allow" ] && printf '%s\n' "$f" | grep -Eq -- "$allow" && continue
      while IFS= read -r hit; do
        # A line that reports the claim as past ("used to say") does not assert it.
        printf '%s\n' "$hit" | grep -Eqi 'used to (say|read|claim)|no longer|formerly said' && continue
        bad+=("$id  $f:${hit%%:*}: $(printf '%s' "${hit#*:}" | cut -c1-110)" "      superseded by: $why")
      done < <(grep -nE -- "$re" "$f" 2>/dev/null)
    done < <(text_files "$r")
  done
done < "$CLAIMS"
if [ "$rows" -eq 0 ]; then fail S4 "the retired-claims register has no rows (nothing checked)" "$CLAIMS"
elif [ "${#bad[@]}" -gt 0 ]; then fail S4 "a retired claim is still asserted" "${bad[@]}"
else pass S4 "none of the $rows retired claims is asserted"; fi

# --- S5: every sibling builds against one commit of the checker -------------
check
pins=()
for r in vocarium hermeneia haec; do
  found=""
  while IFS= read -r f; do
    # A workflow step that checks out trope-checker: its `ref:` if it has one.
    p=$(awk '
      /repository:[[:space:]]*hyperpolymath\/trope-checker/ { inblk = 1; got = 0; next }
      inblk && /^[[:space:]]*-[[:space:]]/ { if (!got) print FILENAME ": unpinned"; inblk = 0 }
      inblk && /ref:[[:space:]]*[0-9a-f]{40}/ { match($0, /[0-9a-f]{40}/); print FILENAME ": " substr($0, RSTART, 40); got = 1; inblk = 0 }
      END { if (inblk && !got) print FILENAME ": unpinned" }' "$f")
    [ -n "$p" ] && found+="$p"$'\n'
    # A script constant.
    p=$(grep -HnoE 'TROPECHECK_PIN="?[0-9a-f]{40}' "$f" 2>/dev/null | sed -E 's/^([^:]+):[0-9]+:.*([0-9a-f]{40})$/\1: \2/')
    [ -n "$p" ] && found+="$p"$'\n'
  done < <(find "$r" -name .git -prune -o -type f \( -name '*.yml' -o -name '*.sh' \) -print)
  [ -n "$found" ] && while IFS= read -r l; do [ -n "$l" ] && pins+=("$l"); done <<<"$found"
done
distinct=$(printf '%s\n' "${pins[@]:-}" | sed -E 's/^.*: //' | sort -u | grep -c . || true)
if [ "${#pins[@]}" -eq 0 ]; then fail S5 "no sibling records which checker commit it builds against (nothing read)"
elif [ "$distinct" -ne 1 ] || printf '%s\n' "${pins[@]}" | grep -q 'unpinned$'; then
  fail S5 "the siblings do not build against one commit of trope-checker" "${pins[@]}"
else pass S5 "every sibling pins trope-checker at $(printf '%s\n' "${pins[0]}" | sed -E 's/^.*: //' | cut -c1-12)"; fi

# --- S6: one revision of the shared scan workflow ---------------------------
check
mapfile -t scan < <(grep -rHnoE 'hypatia-scan-reusable\.yml@[0-9a-f]{40}' --include='*.yml' \
                      "${REPOS[@]/%//.github/workflows}" 2>/dev/null | sed -E 's/^([^:]+):[0-9]+:.*@/\1: /')
distinct=$(printf '%s\n' "${scan[@]:-}" | sed -E 's/^.*: //' | sort -u | grep -c . || true)
if [ "${#scan[@]}" -eq 0 ]; then fail S6 "no repository calls the shared scan workflow (nothing read)"
elif [ "$distinct" -ne 1 ]; then fail S6 "the shared scan workflow is pinned at $distinct revisions" "${scan[@]}"
else pass S6 "one revision of the shared scan workflow in ${#scan[@]} callers"; fi

# --- S7: a README does not cite a root document its repository lacks --------
check
bad=()
for r in "${REPOS[@]}"; do
  [ -f "$r/README.adoc" ] || { bad+=("$r/README.adoc is missing"); continue; }
  while IFS= read -r hit; do
    name=$(printf '%s' "$hit" | sed -E 's/^[0-9]+://')
    [ -e "$r/$name" ] || bad+=("$r/README.adoc:${hit%%:*} cites $name, which $r does not have")
  done < <(grep -noE '(^|[^A-Za-z0-9_/.-])[A-Z][A-Z0-9_-]+\.adoc' "$r/README.adoc" | sed -E 's/^([0-9]+):[^A-Z]*/\1:/' | sort -u)
done
if [ "${#bad[@]}" -gt 0 ]; then fail S7 "a README cites a document that is not there" "${bad[@]}"
else pass S7 "every root document a README cites exists"; fi

# --- S8: no repository still carries the mint template's identity -----------
check
bad=()
for r in "${REPOS[@]}"; do
  [ -d "$r/.machine_readable" ] || continue
  while IFS= read -r hit; do bad+=("$hit"); done < <(
    grep -rnE '^[[:space:]]*(project|canonical-name|repo|kind|domain)[[:space:]]*=[[:space:]]*"(rsr-template-repo|[^"]*\{\{[A-Z_]+\}\}[^"]*)"' \
      --include='*.a2ml' --include='*.deed' "$r/.machine_readable" 2>/dev/null | cut -c1-150)
done
if [ "${#bad[@]}" -gt 0 ]; then fail S8 "template identity left in a repository's own description" "${bad[@]}"
else pass S8 "no template identity in any repository's description"; fi

# --- S9: one value for "coordination" ---------------------------------------
check
mapfile -t coord < <(grep -rHnE '^[[:space:]]*coordination[[:space:]]*=' --include='ECOSYSTEM.a2ml' \
                       "${REPOS[@]/%//.machine_readable}" 2>/dev/null | sed -E 's/^([^:]+:[0-9]+):[[:space:]]*coordination[[:space:]]*=[[:space:]]*/\1: /')
distinct=$(printf '%s\n' "${coord[@]:-}" | sed -E 's/^.*: //' | sort -u | grep -c . || true)
if [ "${#coord[@]}" -eq 0 ]; then pass S9 "no repository declares a coordination value"
elif [ "$distinct" -ne 1 ]; then fail S9 "\"coordination\" has $distinct values across the stack" "${coord[@]}"
else pass S9 "one coordination value in ${#coord[@]} declarations"; fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "stack coherence: $CHECKS checks, all agree"
else
  echo "stack coherence: $FAILS of $CHECKS checks found a disagreement"
  exit 1
fi
