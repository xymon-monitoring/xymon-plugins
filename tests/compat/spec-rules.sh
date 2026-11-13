#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/spec-rules.sh
#
# Every rule SPEC.md numbers -- its **S<n>. lines -- is checked by at least
# one test, which cites it as [S<n>] in an assertion's message, and nothing
# cites a rule that does not exist: a rule nobody tests, or a citation left
# behind by a renumbering, fails the run. The tests are the plugins' and
# tests/compat's, and CI's workflows for what only CI does. Prints which
# tests check each rule.
#
# Reads files only.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)

rules=$(sed -n 's/^\*\*\(S[0-9][0-9]*\)\. .*/\1/p' "$ROOT/SPEC.md")
[ -n "$rules" ] || fail "SPEC.md numbers no rules (**S1. ...)"

# One line per citation: the file's name, then the rule. This file is left
# out: it names the form of a citation, not a rule.
cites=$( { grep -o '\[S[0-9][0-9]*\]' "$ROOT"/plugins/*/tests/*.sh "$ROOT"/tests/compat/*.sh \
		"$ROOT"/.github/workflows/*.yml /dev/null || true; } | { grep -v '/spec-rules\.sh:' || true; } \
	| sed 's|.*/\([^/]*\):\[\(S[0-9]*\)\]|\1 \2|' | sort -u)

missing=""
for r in $rules; do
	by=$(printf '%s\n' "$cites" | sed -n "s/^\([^ ]*\) $r\$/\1/p" | tr '\n' ' ')
	printf '%-4s %s\n' "$r" "${by:-(no test)}"
	[ -n "$by" ] || missing="$missing $r"
done
[ -z "$missing" ] || fail "rules of SPEC.md no test cites:$missing"

for c in $(printf '%s\n' "$cites" | cut -d' ' -f2 | sort -u); do
	grep -qx "$c" <<<"$rules" \
		|| fail "[$c] is cited, and SPEC.md does not number it: $(printf '%s\n' "$cites" | grep " $c\$" | cut -d' ' -f1 | tr '\n' ' ')"
done

pass "every rule SPEC.md numbers is cited by a test, and every citation names one of them"
