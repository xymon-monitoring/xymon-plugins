#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-portability.sh
#
# The plugins' test scripts, and ./install.sh, keep to Xymon's portability rules: bash 3.2,
# portable tool flags and regular expressions, no early-exit pipes under
# pipefail, and the rest of what Xymon's BSD and macOS lanes taught it. The
# rules are Xymon's own, read from XYMON_SRC at each run, not a copy kept
# here: Xymon's tests/buildsystem/test-suite-portability.sh is run over a
# temporary tree laid out as it expects -- its script and assert.sh beside
# this repository's tests/, each plugins/NAME/tests/, under
# tests/plugins/NAME/, and each checks/NAME/tests/, under tests/checks/NAME/
# -- since it checks the tree it sits in.
#
# One rule is left out: interpreter, no python or perl in a test. Xymon's
# BSD lanes have no Python; every plugin here needs it, so a lane without
# Python cannot run the plugins at all.
#
# Skips where XYMON_SRC holds no portability check. Needs XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
check=$XYMON_SRC/tests/buildsystem/test-suite-portability.sh
[ -f "$check" ] || skip "XYMON_SRC has no tests/buildsystem/test-suite-portability.sh"

work=$(mktempdir)
tree=$work/tree
mkdir -p "$tree/tests/buildsystem" "$tree/tests/lib" "$tree/tests/plugins"
cp "$check" "$tree/tests/buildsystem/"
cp "$XYMON_SRC/tests/lib/assert.sh" "$tree/tests/lib/assert-xymon.sh"
# This repository's tests, then each plugin's, where the check looks.
(cd "$ROOT/tests" && tar cf - .) | (cd "$tree/tests" && tar xf -)
for d in "$ROOT"/plugins/*/tests; do
	name=$(basename "$(dirname "$d")")
	mkdir -p "$tree/tests/plugins/$name"
	(cd "$d" && tar cf - .) | (cd "$tree/tests/plugins/$name" && tar xf -)
done
# And each check's, for the checks that have tests.
for d in "$ROOT"/checks/*/tests; do
	[ -d "$d" ] || continue
	name=$(basename "$(dirname "$d")")
	mkdir -p "$tree/tests/checks/$name"
	(cd "$d" && tar cf - .) | (cd "$tree/tests/checks/$name" && tar xf -)
done
# And the installer, which runs on every machine the plugins go to: placed
# where the check looks, and named back as it is here.
cp "$ROOT/install.sh" "$tree/tests/install-sh-under-check.sh"
# The check sources ../lib/assert.sh; this repository has its own file of
# that name, so Xymon's goes in under another, and the check is pointed at it.
sed -e 's|/\.\./lib/assert\.sh"|/../lib/assert-xymon.sh"|' "$tree/tests/buildsystem/$(basename "$check")" \
	> "$work/check.sh"
mv "$work/check.sh" "$tree/tests/buildsystem/$(basename "$check")"

rc=0
bash "$tree/tests/buildsystem/$(basename "$check")" > "$work/report" 2>&1 || rc=$?

# The report gives each violation as "  [RULE] FILE:LINE" and its reason on the
# next, indented line. Keep those of every rule but interpreter, with each
# file named as it is in this repository. The make-tree rules exempt Xymon's
# tests/lib/assert.sh by its name, the one file where its helpers read the
# make tree on purpose; its copy here goes by another name, so it is exempted
# from them the same way, and from nothing else.
awk '
	/^  \[[a-z-]+\] / {
		keep = ($1 != "[interpreter]") && !($1 ~ /^\[make-tree-/ && $2 ~ /^tests\/lib\/assert-xymon\.sh:/)
		if (keep) print; next
	}
	/^      / { if (keep) print; next }
	{ keep = 0 }
' "$work/report" | sed -e 's|tests/plugins/\([^/]*\)/|plugins/\1/tests/|' -e 's|tests/checks/\([^/]*\)/|checks/\1/tests/|' -e 's|tests/install-sh-under-check\.sh|install.sh|' > "$work/violations"

if [ -s "$work/violations" ]; then
	fail "the plugins' tests break Xymon's portability rules:
$(cat "$work/violations")"
fi
# Exited with an error for something other than violations -- a rule's own
# self-test, a helper missing -- is a failure of its own, not a pass.
if [ "$rc" -ne 0 ] && ! grep -q 'violation(s); see above' "$work/report"; then
	fail "Xymon's portability check did not run: $(tail -n 5 "$work/report")"
fi

pass "the plugins' tests and install.sh keep to Xymon's portability rules, but the one against Python, which every plugin needs"
