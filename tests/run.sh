#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/run.sh -- run the tests in each DIR, by default every one: each
# plugin's, under plugins/<name>/tests/, each check's that has some, under
# checks/<name>/tests/, then those of how the plugins fit together, under
# tests/compat/, against the built Xymon source tree named by XYMON_SRC.
# Given plugins/NAME/tests, it runs that plugin's alone.
#
#   XYMON_SRC=/path/to/xymon tests/run.sh [DIR...]
#
# A test passes with 0, skips with 77 -- something it needs is not installed,
# and it says what -- and fails with anything else. The run fails if any test
# fails; with XYMONAPI_NO_SKIP=1 a skip fails it too, which is how CI makes
# sure every test really ran.

cd "$(dirname "$0")/.." || exit 2
[ "$#" -gt 0 ] || set -- plugins/*/tests $(for d in checks/*/tests; do [ -d "$d" ] && echo "$d"; done) tests/compat
pass=0 skip=0 fail=0
for t in $(for d in "$@"; do ls "$d"/*.sh; done); do
	echo "----- $t -----"
	rc=0
	bash "$t" || rc=$?
	case $rc in
		0)  pass=$((pass + 1)) ;;
		77) skip=$((skip + 1)) ;;
		*)  fail=$((fail + 1)); echo "FAIL: $t (rc=$rc)" ;;
	esac
done
echo "----- passed: $pass, skipped: $skip, failed: $fail -----"
[ "$fail" -eq 0 ] || exit 1
if [ "${XYMONAPI_NO_SKIP:-}" = 1 ] && [ "$skip" -ne 0 ]; then
	echo "XYMONAPI_NO_SKIP=1, and $skip test(s) skipped" >&2
	exit 1
fi
exit 0
