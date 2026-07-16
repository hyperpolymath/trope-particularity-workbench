#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-no-vlang.sh — enforce "the V language (vlang) is banned in the estate".
#
# Estate rule: V (vlang.io) is banned. The connector layer is
# `zig-unified-api-adapter` (16 endpoints + transaction-firewall gating).
# Treat any V-language reference as drift and remove it.
#
# NOTE: an earlier revision of this script had "V" globally substituted to
# "zig" in its prose and pattern list ("ziguage", a bare 'zig' pattern twice),
# which made the check ban Zig — contradicting the estate's own ANCHOR
# implementation-policy (Zig is allowed: it is the FFI standard) and the
# script's own remediation message (the replacement adapter's name contains
# "zig"). Restored to the V-language ban; evidence of original intent:
# hermeneia's copy line 85 ("V has been replaced by zig-unified-api-adapter")
# and the DOC_EXCLUSIONS entry feedback_v_lang_banned.md below.
#
# Searches for V-specific patterns in tracked files. The .v file
# extension is intentionally NOT used as a marker because Coq theorem files
# share that extension; this check looks at content patterns instead.
#
# Excludes:
#   .git/ (vcs internals)
#   affinescript/ (a separately-licensed AffineScript subtree; pattern hits
#       there are not estate-managed and false-positive on `.v` mentions in
#       linguistic / academic prose).
#
# Exit codes:
#   0 — no V-language references found
#   1 — V-language references found (treat as drift)
#   2 — usage / setup error

set -euo pipefail

REPO_ROOT="${1:-.}"

# Patterns that uniquely indicate V code, scaffolding, or naming.
# Coq's `.v` extension and the affinescript subtree are excluded by path.
PATTERNS=(
    'gen-v-connector'
    'V-TRIPLE'
    'v-triple'
    'vlang'
    'connectors/v-'
)

PATTERN_OR=$(IFS='|'; echo "${PATTERNS[*]}")

# Files that document the V ban itself (the rule's own description
# legitimately names "vlang", "V-TRIPLE", etc.). Excluded by name.
DOC_EXCLUSIONS=(
    "estate-rules.yml"             # the workflow that calls this script
    "check-no-vlang.sh"            # this script itself
    "PLAYBOOK.a2ml"                # documents the [rsr-repo-skeleton] rules
    "feedback_v_lang_banned.md"    # memory entry documenting the ban
    "project_zig_unified_api.md"   # memory entry documenting the replacement
)

EXCLUDE_ARGS=()
for f in "${DOC_EXCLUSIONS[@]}"; do
    EXCLUDE_ARGS+=(--exclude="$f")
done

# Build grep arguments. Use -r to recurse, -n for line numbers, -i for
# case-insensitive matching. Exclude .git, the affinescript subtree, and
# files that legitimately document the ban.
HITS=$(grep -rni -E "$PATTERN_OR" "$REPO_ROOT" \
    --exclude-dir=.git \
    --exclude-dir=affinescript \
    --exclude-dir=node_modules \
    "${EXCLUDE_ARGS[@]}" \
    2>/dev/null || true)

if [ -z "$HITS" ]; then
    echo "PASS: no V-language references"
    exit 0
fi

# Count matches
LINES=$(echo "$HITS" | wc -l | tr -d ' ')

echo "FAIL: $LINES V-language reference(s) found (estate rule: V (vlang) is banned):" >&2
echo "$HITS" | sed 's|^|  |' >&2
echo "" >&2
echo "V has been replaced by zig-unified-api-adapter. Remove these references." >&2
exit 1
