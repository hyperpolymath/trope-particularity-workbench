# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# trope-particularity-workbench is a documentation repo; these are its only gates.

set shell := ["bash", "-uc"]

# Show the available recipes
default:
    @just --list --unsorted

# The nine effects agree across vocabulary, trainer, map and README
check:
    bash tests/check-vocabulary.sh

# Root shape and AsciiDoc-by-default (the estate-rules workflow)
estate-rules:
    bash scripts/check-root-shape.sh .
    bash scripts/check-no-md-in-docs.sh .
