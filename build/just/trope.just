# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Particularity workbench recipes. No Python. Imported via import? "build/just/trope.just"

# Consistency gate: the nine effects agree across vocabulary, trainer, map, README.
check: vocabulary-check

vocabulary-check:
    bash tests/check-vocabulary.sh
