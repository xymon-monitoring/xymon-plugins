#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-status.sh
#
# status-server says, for each server plugin of this checkout, whether it is
# installed, the version installed -- its VERSION, a release tag read as its
# X.Y.Z -- whether its task is on, and the version this checkout has, with
# "newer" when it is newer than the one installed; status-tools the same on
# your own machine, without on or off. A plugin named is the only one told
# of; a name that is no plugin is refused. status installs, enables and
# removes nothing.
#
# Installed into a scratch directory.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
here=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymonapi/PLUGIN")

st() { "$ROOT/install.sh" status-server "$@" XYMONHOME="$home" 2>&1; }

ls -laR "$home" > "$work/before"
assert_contains "xymonapi: not installed; this checkout has $here" "$(st)" "[S15] a plugin not installed is said to be"
ls -laR "$home" > "$work/after"
cmp -s "$work/before" "$work/after" || fail "[S15] status changed the tree: $(diff "$work/before" "$work/after")"

"$ROOT/install.sh" install-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "install-server failed: $(tail -n 5 "$work/install.log")"
find "$home" | sort > "$work/before"
out=$(st)
assert_contains "xymonapi: $here installed, off; this checkout has $here" "$out" "[S15] installed, its version, off"
assert_not_contains "newer" "$out" "[S15] nothing newer when the versions agree"
find "$home" | sort > "$work/after"
cmp -s "$work/before" "$work/after" || fail "[S15] status changed the installation: $(diff "$work/before" "$work/after")"

"$ROOT/install.sh" enable-server xymonapi XYMONHOME="$home" >/dev/null 2>&1 || fail "enable-server failed"
assert_contains "xymonapi: $here installed, on;" "$(st xymonapi)" "[S15] on once enabled"
assert_equal 1 "$(st xymonapi | wc -l | tr -d ' ')" "[S15] a plugin named is the only one told of"

echo "xymonapi/v0.0.1" > "$home/ext/xymonapi/VERSION"
assert_contains "xymonapi: 0.0.1 installed, on; this checkout has $here, newer" "$(st xymonapi)" "[S15] an older install, by its release tag, has a newer version here"

rc=0
st no-such-plugin > "$work/bad" || rc=$?
[ "$rc" -ne 0 ] || fail "[S15] status of a name that is no plugin succeeded"

prefix=$work/tools
"$ROOT/install.sh" install-tools xymonapi PREFIX="$prefix" >"$work/tools.log" 2>&1 || fail "install-tools failed: $(tail -n 5 "$work/tools.log")"
out=$("$ROOT/install.sh" status-tools xymonapi PREFIX="$prefix" 2>&1)
assert_contains "xymonapi: $here installed; this checkout has $here" "$out" "[S15] status-tools: installed, its version, no on or off"

pass "status-server and status-tools say what is installed, at which version, whether its task is on, and whether this checkout is newer, changing nothing"
