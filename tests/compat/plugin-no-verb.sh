#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-no-verb.sh
#
# install.sh run with no verb and no terminal prints its usage, exits 2 and
# changes nothing, settings given or not: a script that forgot its verb
# installs, enables and removes nothing.
#
# Run against a scratch directory, with no terminal: stdin from /dev/null,
# stdout and stderr to a file.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)

# no_verb LABEL [NAME=value...] -- run install.sh with no verb, and check.
no_verb() {
	label=$1; shift
	rc=0
	"$ROOT/install.sh" "$@" </dev/null >"$work/$label.log" 2>&1 || rc=$?
	assert_equal 2 "$rc" "[S17] $label: exits 2"
	assert_contains "usage: ./install.sh" "$(cat "$work/$label.log")" "[S17] $label: prints the usage"
	[ -z "$(ls -A "$work/home" "$work/prefix" "$work/man" 2>/dev/null)" ] \
		|| fail "[S17] $label: changed something: $(ls -AR "$work/home" "$work/prefix" "$work/man" 2>/dev/null)"
}

XYMONHOME=$work/home PREFIX=$work/prefix MANDIR=$work/man no_verb "no word"
no_verb "settings only" XYMONHOME="$work/home" PREFIX="$work/prefix" MANDIR="$work/man"

pass "install.sh with no verb and no terminal prints its usage, exits 2 and changes nothing"
