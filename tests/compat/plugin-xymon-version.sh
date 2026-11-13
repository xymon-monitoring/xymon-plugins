#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-xymon-version.sh
#
# A server plugin's xymon: line names the lowest Xymon it works with, and
# install-server compares it with what $XYMONHOME/bin/xymon --version gives:
# an older Xymon is refused, naming both versions, before anything is
# installed, unless --force, which installs and says so; a plugin that needs
# the refused one is refused with it; a development version comes after the
# release before it and before its own: 4.3.30-dev is refused, 4.3.31-dev
# installs with a warning, 4.3.32-dev without; versions compare by number,
# 4.10 after 4.9; a Xymon whose version cannot be read installs, with a warning. Every
# xymon: line is X.Y.Z.
#
# Installed into a scratch directory, with a stand-in bin/xymon that prints
# the version the test chooses.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
want=$(sed -n 's/^xymon: *//p' "$ROOT/plugins/xymonapi/PLUGIN")
[ -n "$want" ] || fail "[S14] plugins/xymonapi/PLUGIN has no xymon: line"
for f in "$ROOT"/plugins/*/PLUGIN; do
	v=$(sed -n 's/^xymon: *//p' "$f")
	[ -z "$v" ] || grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$v" || fail "[S14] $f: xymon: $v is not X.Y.Z"
done

# server VERSION -- h, a new scratch server whose bin/xymon gives that
# version, or none when VERSION is empty.
n=0
server() {
	n=$((n + 1)); h=$work/s$n
	mkdir -p "$h/bin"
	[ -z "$1" ] || printf '#!/bin/sh\necho "Xymon version %s"\n' "$1" > "$h/bin/xymon"
	[ -z "$1" ] || chmod 755 "$h/bin/xymon"
}
# try [ARG...] PLUGIN -- install-server on $h; its exit code in rc, its
# output in $work/log.
try() {
	rc=0
	"$ROOT/install.sh" install-server "$@" XYMONHOME="$h" MANDIR="$work/man" >"$work/log" 2>&1 || rc=$?
}

server 4.3.30
try xymonapi
[ "$rc" -ne 0 ] || fail "[S14] xymonapi installed on Xymon 4.3.30, below its $want"
assert_contains "needs Xymon $want or newer, and this server's is 4.3.30" "$(cat "$work/log")" "[S14] the refusal names both versions"
[ -e "$h/ext" ] && fail "[S14] the refused install left something in ext/"

try xymonapi-rag
[ "$rc" -ne 0 ] || fail "[S14] xymonapi-rag, which needs xymonapi, installed on Xymon 4.3.30"
[ -e "$h/ext" ] && fail "[S14] the refused install of xymonapi-rag left something in ext/"

try --force xymonapi
[ "$rc" -eq 0 ] || fail "[S14] --force did not install: $(tail -n 3 "$work/log")"
assert_file_exists "$h/ext/xymonapi/VERSION"
assert_contains "installed anyway, as --force asks" "$(cat "$work/log")" "[S14] --force says it installed anyway"

next=$(awk -F. -v OFS=. '{ $3 += 1; print }' <<<"$want")
for v in "$want" "$next-dev" 4.10.0 99.0.0; do
	server "$v"
	try xymonapi
	[ "$rc" -eq 0 ] || fail "[S14] xymonapi refused on Xymon $v: $(tail -n 3 "$work/log")"
	assert_not_contains "needs Xymon" "$(cat "$work/log")" "[S14] nothing said of Xymon $v"
done

server 4.3.30-dev
try xymonapi
[ "$rc" -ne 0 ] || fail "[S14] xymonapi installed on Xymon 4.3.30-dev"

server "$want-dev"
try xymonapi
[ "$rc" -eq 0 ] || fail "[S14] xymonapi refused on Xymon $want-dev: $(tail -n 3 "$work/log")"
assert_contains "on the way to $want: not checked" "$(cat "$work/log")" "[S14] and it says $want-dev may lack what $want needs"

server ""
try xymonapi
[ "$rc" -eq 0 ] || fail "[S14] xymonapi refused where Xymon's version cannot be read: $(tail -n 3 "$work/log")"
assert_contains "could not be read: not checked" "$(cat "$work/log")" "[S14] and it says the version was not checked"

# A xymonserver.cfg that does not read xymonserver.d/, as one kept from
# before 4.3.31: the install says so, and how to fix it; one that does, or
# none at all, nothing.
server 4.3.31
mkdir -p "$h/etc"
echo 'XYMONSERVERHOSTNAME="x"' > "$h/etc/xymonserver.cfg"
try xymonapi
[ "$rc" -eq 0 ] || fail "[S14] the install failed over a xymonserver.cfg without xymonserver.d: $(tail -n 3 "$work/log")"
assert_contains "does not read xymonserver.d/" "$(cat "$work/log")" "[S14] the install says xymonserver.cfg ignores the plugins' settings"
assert_contains "optional directory $h/etc/xymonserver.d" "$(cat "$work/log")" "[S14] and gives the line to add"
for line in "optional directory $h/etc/xymonserver.d" "directory $h/etc/xymonserver.d" \
	"directory $h/etc/xymonserver.d/" "directory xymonserver.d" "  optional   directory   xymonserver.d/  "; do
	server 4.3.31
	mkdir -p "$h/etc"
	printf 'XYMONSERVERHOSTNAME="x"\n%s\n' "$line" > "$h/etc/xymonserver.cfg"
	try xymonapi
	assert_not_contains "does not read xymonserver.d" "$(cat "$work/log")" "[S14] nothing said when xymonserver.cfg has: $line"
done

pass "install-server refuses a plugin whose xymon: line is newer than the server's Xymon, and one that needs it, unless --force; -dev counts as its release, versions compare by number, and an unreadable version installs with a warning"
