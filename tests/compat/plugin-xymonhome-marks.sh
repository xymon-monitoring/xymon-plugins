#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-xymonhome-marks.sh
#
# A server action acts only on a server's tree: the tree XYMONHOME names is
# read for Xymon's marks, a whole pair before any single mark. A server's
# (etc/xymonserver.cfg, bin/xymond) is used, client files beside it or not;
# a client's (etc/xymonclient.cfg, bin/xymonclient.sh) is refused, also
# where it shares a server's etc/ as on Debian; part of a pair and no marks
# at all are refused, before anything changes -- so that a mistyped
# XYMONHOME neither creates a tree nor removes a manual page. Under DESTDIR
# no marks are read. Without XYMONHOME, the trees found are named.
#
# Installed into scratch trees; XYMON_PLUGINS_TREES points detection at them.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
man=$work/man

# tree DIR MARK... -- a scratch tree holding those marks.
tree() {
	d=$1; shift
	mkdir -p "$d"
	for m in "$@"; do mkdir -p "$d/$(dirname "$m")"; : > "$d/$m"; done
}
# run ACTION HOME [NAME=value...] -- install.sh ACTION xymonapi on HOME,
# its output in out, its exit code in rc.
run() {
	a=$1; h=$2; shift 2
	rc=0; out=$("$ROOT/install.sh" "$a" xymonapi XYMONHOME="$h" MANDIR="$man" "$@" </dev/null 2>&1) || rc=$?
}
# refused LABEL HOME TEXT -- install-server on HOME fails, says TEXT and
# leaves HOME as it was.
refused() {
	find "$2" | sort > "$work/before"
	run install-server "$2"
	[ "$rc" -ne 0 ] || fail "[S18] $1: install-server succeeded"
	assert_contains "$3" "$out" "[S18] $1: refused, saying so"
	find "$2" | sort > "$work/after"
	cmp -s "$work/before" "$work/after" || fail "[S18] $1: the refusal changed the tree: $(diff "$work/before" "$work/after")"
}

tree "$work/client" etc/xymonclient.cfg bin/xymonclient.sh
refused "a client's tree" "$work/client" "is a Xymon client's tree"

tree "$work/debian-client" etc/xymonserver.cfg etc/xymonclient.cfg bin/xymonclient.sh
refused "a client's tree sharing a server's etc/" "$work/debian-client" "is a Xymon client's tree"

tree "$work/half" etc/xymonserver.cfg
refused "half a server's pair" "$work/half" "it has etc/xymonserver.cfg, and a server's has etc/xymonserver.cfg bin/xymond"

tree "$work/bare"
refused "a tree with no marks" "$work/bare" "none of etc/xymonserver.cfg bin/xymond is there"
[ -e "$man" ] && fail "[S18] a tree with no marks: a manual page was installed"
# Every server action, named or not, is refused the same.
find "$work/bare" | sort > "$work/before"
for a in install-server enable-server disable-server status-server uninstall-server venv-server; do
	for p in xymonapi ""; do
		rc=0
		"$ROOT/install.sh" "$a" $p XYMONHOME="$work/bare" MANDIR="$man" </dev/null >"$work/a.log" 2>&1 || rc=$?
		[ "$rc" -ne 0 ] || fail "[S18] $a ${p:-(every plugin)} on a tree with no marks succeeded"
		assert_contains "none of etc/xymonserver.cfg bin/xymond is there" "$(cat "$work/a.log")" "[S18] $a ${p:-(every plugin)}: refused for the marks"
	done
done
find "$work/bare" | sort > "$work/after"
cmp -s "$work/before" "$work/after" || fail "[S18] a refused action changed the tree: $(diff "$work/before" "$work/after")"
[ -e "$man" ] && fail "[S18] a refused action touched MANDIR"

server_tree "$work/server"
: > "$work/server/etc/xymonclient.cfg"; : > "$work/server/bin/xymonclient.sh"
run install-server "$work/server"
[ "$rc" -eq 0 ] || fail "[S18] a server's tree with a client's files beside: install-server failed: $out"
assert_file_exists "$work/server/ext/xymonapi/VERSION"
m=$(first_line "$(find "$man" -type f -name 'xymonapi.*')")
[ -n "$m" ] || fail "install-server installed no manual page under $man"

# A mistyped XYMONHOME removes nothing: not the manual page the real
# server's install put in MANDIR.
run uninstall-server "$work/sever"
[ "$rc" -ne 0 ] || fail "[S18] uninstall-server on a mistyped XYMONHOME succeeded"
assert_file_exists "$m"
[ -e "$work/sever" ] && fail "[S18] uninstall-server on a mistyped XYMONHOME created it"

run install-server /usr/lib/xymon/server DESTDIR="$work/stage"
[ "$rc" -eq 0 ] || fail "[S18] under DESTDIR, install-server failed: $out"
assert_file_exists "$work/stage/usr/lib/xymon/server/ext/xymonapi/VERSION"

rc=0
out=$(XYMON_PLUGINS_TREES="$work/server:$work/client:$work/half:$work/debian-client" \
	"$ROOT/install.sh" install-server xymonapi MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S18] install-server without XYMONHOME succeeded"
assert_contains "$work/server, a Xymon server" "$out" "[S18] without XYMONHOME, the server's tree found is named"
assert_contains "$work/client, a Xymon client" "$out" "[S18] and the client's"
assert_contains "$work/debian-client, a Xymon client" "$out" "[S18] a client sharing a server's etc/ named a client"
assert_not_contains "$work/half," "$out" "[S18] part of a pair is no Xymon tree found"

# Under DESTDIR without XYMONHOME, the host's trees are not read.
rc=0
out=$(XYMON_PLUGINS_TREES="$work/server" "$ROOT/install.sh" status-server DESTDIR="$work/stage" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S18] status-server under DESTDIR without XYMONHOME succeeded"
assert_not_contains "$work/server" "$out" "[S18] under DESTDIR, no tree of the host is read"

pass "a server action acts only on a server's tree: a client's, part of a pair and an unmarked tree are refused before anything changes, a mistyped XYMONHOME removes no manual page, DESTDIR reads no marks, and without XYMONHOME the trees found are named"
