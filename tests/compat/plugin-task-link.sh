#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-task-link.sh
#
# A plugin's task file lives in its directory, ext/PLUGIN/tasks.cfg, and
# tasks.d/PLUGIN is a link to it, so that removing ext/PLUGIN by hand takes
# the task with it: xymonlaunch, reading tasks.d as its tasks.cfg says, no
# longer has the task, and says nothing about the link that points nowhere.
# The next uninstall-server removes that link. A task file an older install
# copied into tasks.d -- one an admin may have enabled -- is moved into the
# plugin's directory, as it was, and replaced by the link; a link to
# something else at tasks.d/PLUGIN is left alone. Under DESTDIR, the link
# names the installed task file.
#
# Installed into a scratch directory; xymonlaunch is the one built in the
# Xymon tree in XYMON_SRC, run with --dump, so no task runs.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
launch=$XYMON_SRC/common/xymonlaunch
[ -x "$launch" ] || skip "xymonlaunch is not built in $XYMON_SRC"

install() { "$ROOT/install.sh" install-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/$1.log" 2>&1 \
	|| fail "install-server ($1) failed: $(tail -n 5 "$work/$1.log")"; }
# The tasks xymonlaunch sees, as tasks.cfg reads tasks.d; its stderr apart.
tasks() { "$launch" --config="$home/etc/tasks.cfg" --dump 2>"$work/dump.err" | grep '^\[' || true; }

mkdir -p "$home/etc"
printf 'directory %s/etc/tasks.d\n' "$home" > "$home/etc/tasks.cfg"

install first
link=$home/etc/tasks.d/xymonapi
[ -L "$link" ] || fail "tasks.d/xymonapi is not a link"
assert_equal "$home/ext/xymonapi/tasks.cfg" "$(readlink "$link")" "[S6] tasks.d/xymonapi links to the plugin's tasks.cfg"
assert_contains "[xymonapi]" "$(tasks)" "xymonlaunch reads the task through the link"

rm -rf "$home/ext/xymonapi"
if [ ! -L "$link" ] || [ -e "$link" ]; then fail "removing ext/xymonapi did not leave the link pointing nowhere"; fi
seen=$(tasks)
assert_not_contains "[xymonapi]" "$seen" "[S9] xymonlaunch no longer has the task once ext/xymonapi is gone"
# xymonlaunch always says it loads the configuration; anything else would be
# about the link.
other=$(grep -v 'Loading tasklist configuration' "$work/dump.err" || true)
[ -z "$other" ] || fail "[S9] xymonlaunch complained about the link that points nowhere: $other"

"$ROOT/install.sh" uninstall-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/uninstall.log" 2>&1 \
	|| fail "uninstall-server after the removal by hand failed: $(tail -n 5 "$work/uninstall.log")"
if [ -e "$link" ] || [ -L "$link" ]; then fail "[S9] uninstall-server left the link that pointed nowhere"; fi

# An older install's copy in tasks.d, enabled by the admin: moved, as it was.
mkdir -p "$home/etc/tasks.d"
sed -e "s|@XYMONHOME@|$home|g" "$ROOT/plugins/xymonapi/$(sed -n 's/^task: *//p' "$ROOT/plugins/xymonapi/PLUGIN")" \
	| grep -v '^[[:space:]]*DISABLED$' > "$link"
cp "$link" "$work/enabled"
install migrate
[ -L "$link" ] || fail "the older install's task file was not replaced by the link"
cmp -s "$work/enabled" "$home/ext/xymonapi/tasks.cfg" || fail "[S6] the older install's task file was not moved as it was"
assert_contains "moved to" "$(cat "$work/migrate.log")" "the install says it moved the task file"

# A link to something else is left alone.
"$ROOT/install.sh" uninstall-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >/dev/null 2>&1 || true
ln -s /elsewhere "$link"
rc=0
"$ROOT/install.sh" install-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/foreign.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "[S6] install-server over a link to something else succeeded"
assert_equal /elsewhere "$(readlink "$link")" "[S6] the link to something else is left as it was"

# Staged for a package: the link names where the task file will be, not
# where DESTDIR puts it.
"$ROOT/install.sh" install-server xymonapi XYMONHOME=/usr/lib/xymon/server DESTDIR="$work/stage" MANDIR=/usr/share/man >"$work/stage.log" 2>&1 \
	|| fail "install-server with DESTDIR failed: $(tail -n 5 "$work/stage.log")"
assert_equal /usr/lib/xymon/server/ext/xymonapi/tasks.cfg "$(readlink "$work/stage/usr/lib/xymon/server/etc/tasks.d/xymonapi")" \
	"[S6] under DESTDIR the link names the installed task file"

pass "a plugin's task lives in ext/PLUGIN and is linked from tasks.d: removing ext/PLUGIN takes it from xymonlaunch silently, uninstall-server removes the link left, an older copy is moved as it was, a foreign link is left alone, and under DESTDIR the link names the installed path"
