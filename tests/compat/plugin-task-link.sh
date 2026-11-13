#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-task-link.sh
#
# A plugin's task file lives in its directory, ext/PLUGIN/tasks.cfg, and the
# task is on when tasks.d/PLUGIN, a link to it, is there: an install makes no
# link, enable-server makes it and disable-server removes it, and
# xymonlaunch, reading tasks.d as its tasks.cfg says, has the task exactly
# when the link is there. Removing ext/PLUGIN by hand takes the task with
# it, and xymonlaunch says nothing about the link that points nowhere; the
# next uninstall-server removes that link. An older install's task is moved
# to the link: a copy in tasks.d is moved into the plugin's directory as it
# was, and linked unless it was DISABLED; a task file in ext/PLUGIN with a
# DISABLED line, linked or not, loses the line and the link. A link to
# something else at tasks.d/PLUGIN is left alone, by install and enable
# alike. Under DESTDIR, the link names the installed task file.
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
# enable-server, disable-server: run as $1, logged to $work/$1.log.
switch() { "$ROOT/install.sh" "$1-server" xymonapi XYMONHOME="$home" >"$work/$1.log" 2>&1; }
# The tasks xymonlaunch sees, as tasks.cfg reads tasks.d; its stderr apart.
tasks() { "$launch" --config="$home/etc/tasks.cfg" --dump 2>"$work/dump.err" | grep '^\[' || true; }

mkdir -p "$home/etc"
printf 'directory %s/etc/tasks.d\n' "$home" > "$home/etc/tasks.cfg"
link=$home/etc/tasks.d/xymonapi
tf=$home/ext/xymonapi/tasks.cfg

install first
if [ -e "$link" ] || [ -L "$link" ]; then fail "[S13] the install made tasks.d/xymonapi"; fi
assert_not_contains "[xymonapi]" "$(tasks)" "[S13] xymonlaunch has no task of a plugin only installed"

switch enable || fail "enable-server failed: $(cat "$work/enable.log")"
[ -L "$link" ] || fail "[S13] enable-server made no link at tasks.d/xymonapi"
assert_equal "$tf" "$(readlink "$link")" "[S6] tasks.d/xymonapi links to the plugin's tasks.cfg"
assert_contains "[xymonapi]" "$(tasks)" "[S13] xymonlaunch reads the task through the link once enabled"
switch enable || fail "enable-server a second time failed: $(cat "$work/enable.log")"
assert_contains "on already" "$(cat "$work/enable.log")" "[S13] enabling a task on says so"

install again
[ -L "$link" ] || fail "[S13] an install turned off the task the admin had enabled"

switch disable || fail "disable-server failed: $(cat "$work/disable.log")"
if [ -e "$link" ] || [ -L "$link" ]; then fail "[S13] disable-server left tasks.d/xymonapi"; fi
assert_not_contains "[xymonapi]" "$(tasks)" "[S13] xymonlaunch no longer has the task once disabled"
install off
if [ -e "$link" ] || [ -L "$link" ]; then fail "[S13] an install turned on the task the admin had disabled"; fi

switch enable || fail "enable-server failed: $(cat "$work/enable.log")"
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

# An older install's copy in tasks.d: enabled by the admin, it is moved as
# it was and linked; with its DISABLED line, moved without it, and off.
mkdir -p "$home/etc/tasks.d"
sed -e "s|@XYMONHOME@|$home|g" "$ROOT/plugins/xymonapi/$(sed -n 's/^task: *//p' "$ROOT/plugins/xymonapi/PLUGIN")" > "$work/enabled"
cp "$work/enabled" "$link"
install migrate
[ -L "$link" ] || fail "[S6] the older install's enabled task file was not replaced by the link"
cmp -s "$work/enabled" "$tf" || fail "[S6] the older install's task file was not moved as it was"
assert_contains "moved to" "$(cat "$work/migrate.log")" "the install says it moved the task file"

"$ROOT/install.sh" uninstall-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >/dev/null 2>&1
awk '{ print } /^\[xymonapi\]$/ { print "\tDISABLED" }' "$work/enabled" > "$link"
grep -q DISABLED "$link" || fail "the test's DISABLED copy has no DISABLED line"
install migrate-off
if [ -e "$link" ] || [ -L "$link" ]; then fail "[S13] an older install's DISABLED task file was left on"; fi
grep -q DISABLED "$tf" && fail "[S13] the DISABLED line stayed in the moved task file"
assert_contains "enable-server xymonapi" "$(cat "$work/migrate-off.log")" "[S13] the install says how to turn it on"

# A task file in ext/ with a DISABLED line and its link, as the install
# before this one left it: off, the line taken out.
awk '{ print } /^\[xymonapi\]$/ { print "\tDISABLED" }' "$work/enabled" > "$tf"
ln -s "$tf" "$link"
install linked-disabled
if [ -e "$link" ] || [ -L "$link" ]; then fail "[S13] a DISABLED task file with its link was left on"; fi
grep -q DISABLED "$tf" && fail "[S13] the DISABLED line stayed in the task file"

# The link replaced by a regular file, as "sed -i" or an editor that writes
# by renaming does when the admin edits the task through tasks.d: the file
# xymonlaunch reads is the one kept, on, not the copy set aside, and a
# second install finds nothing left to do.
"$ROOT/install.sh" uninstall-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >/dev/null 2>&1
install relink
switch enable || fail "enable-server failed: $(cat "$work/enable.log")"
{ cat "$link"; echo '# the admin edit'; } > "$link.new"
mv "$link.new" "$link"
if [ -L "$link" ]; then fail "the test did not replace the link by a regular file"; fi
cp "$link" "$work/renamed"
install renamed
[ -L "$link" ] || fail "[S6] the regular file that replaced the link was not replaced by the link"
cmp -s "$work/renamed" "$tf" || fail "[S6] the file xymonlaunch was reading was not the one kept"
if [ -e "$home/ext/.xymonapi.tasks.cfg" ]; then fail "[S6] the task file set aside was left in ext/"; fi
install renamed-again
cmp -s "$work/renamed" "$tf" || fail "[S6] a second install did not keep the edited task file"
[ -L "$link" ] || fail "[S13] a second install turned the edited task off"
"$ROOT/install.sh" uninstall-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >/dev/null 2>&1
install before-foreign

# A link to something else is left alone, by install and enable.
ln -s /elsewhere "$link"
rc=0
"$ROOT/install.sh" install-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/foreign.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "[S6] install-server over a link to something else succeeded"
assert_file_exists "$tf"
rc=0; switch enable || rc=$?
[ "$rc" -ne 0 ] || fail "[S6] enable-server over a link to something else succeeded"
assert_contains "left alone" "$(cat "$work/enable.log")" "[S6] and says the link is not the plugin's"
rc=0; switch disable || rc=$?
[ "$rc" -ne 0 ] || fail "[S6] disable-server of a link to something else succeeded"
assert_contains "left alone" "$(cat "$work/disable.log")" "[S6] and says the link is not the plugin's"
assert_equal /elsewhere "$(readlink "$link")" "[S6] the link to something else is left as it was"

# Staged for a package: the link names where the task file will be, not
# where DESTDIR puts it.
"$ROOT/install.sh" install-server xymonapi XYMONHOME=/usr/lib/xymon/server DESTDIR="$work/stage" MANDIR=/usr/share/man >"$work/stage.log" 2>&1 \
	|| fail "install-server with DESTDIR failed: $(tail -n 5 "$work/stage.log")"
"$ROOT/install.sh" enable-server xymonapi XYMONHOME=/usr/lib/xymon/server DESTDIR="$work/stage" >"$work/stage-on.log" 2>&1 \
	|| fail "enable-server with DESTDIR failed: $(tail -n 5 "$work/stage-on.log")"
assert_equal /usr/lib/xymon/server/ext/xymonapi/tasks.cfg "$(readlink "$work/stage/usr/lib/xymon/server/etc/tasks.d/xymonapi")" \
	"[S6] under DESTDIR the link names the installed task file"

pass "a plugin's task lives in ext/PLUGIN and is on when tasks.d links to it: install leaves it off, enable-server and disable-server switch it and installs keep the choice, removing ext/PLUGIN takes it from xymonlaunch silently, older installs move to the link, a foreign link is left alone, and under DESTDIR the link names the installed path"
