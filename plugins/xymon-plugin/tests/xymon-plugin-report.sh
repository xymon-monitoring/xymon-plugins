#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymon-plugin/tests/xymon-plugin-report.sh
#
# The plugins column: install --server xymon-plugin puts its task in place,
# off; enable links it. Its reporter, run as the task would be, sends this
# host's status "plugins", valid 31 hours, from the installer's outdated:
# green when every plugin is up to date; yellow when a newer release is
# published, or a VERSION cannot be compared, or outdated ends otherwise;
# nothing when GitHub is not reached, so that the status there stays and
# goes purple. It waits a time drawn up to XYMON_PLUGINS_WAIT; it says
# where a send fails. The network and Xymon are never reached: xymon, gh,
# curl and sleep are stand-ins first on PATH.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
want=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymon-plugin/PLUGIN")

"$ROOT/xymon-plugin" install --server xymon-plugin XYMONHOME="$home" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "install --server xymon-plugin failed: $(tail -n 5 "$work/install.log")"
ext=$home/ext/xymon-plugin
[ -x "$ext/xymon-plugin-report.sh" ] || fail "the reporter installed is not executable"
assert_file_exists "$ext/tasks.cfg"
if [ -e "$home/etc/tasks.d/xymon-plugin.cfg" ] || [ -L "$home/etc/tasks.d/xymon-plugin.cfg" ]; then
	fail "[S5] installing it turned the plugins column's task on"
fi
assert_contains "CMD \$XYMONHOME/ext/xymon-plugin/xymon-plugin-report.sh" "$(cat "$ext/tasks.cfg")" "[S33] the task runs the reporter"
assert_contains "ENVFILE $home/etc/xymonserver.cfg" "$(cat "$ext/tasks.cfg")" "[S33] with this server's environment"
assert_contains "MAXTIME 7h" "$(cat "$ext/tasks.cfg")" "[S33] bounded in time"
printf 'directory %s/etc/tasks.d\n' "$home" >> "$home/etc/tasks.cfg"
"$ROOT/xymon-plugin" enable --server xymon-plugin XYMONHOME="$home" >"$work/enable.log" 2>&1 \
	|| fail "enable --server xymon-plugin failed: $(tail -n 5 "$work/enable.log")"
[ -L "$home/etc/tasks.d/xymon-plugin.cfg" ] || fail "[S13] enable did not link the plugins column's task"

# The stand-ins: xymon keeps what it was given, or fails with XYMONFAIL;
# gh hangs, as one GitHub does not answer may: the reporter must never run
# it, MAXTIME stopping the reporter and not what it started; curl prints
# the releases in $work/tags as GitHub's API, or fails with CURL=fail;
# sleep keeps how long it was asked to wait, and waits not.
bin=$work/bin; mkdir -p "$bin"
cat > "$bin/xymon" <<'SH'
#!/bin/sh
[ -n "${XYMONFAIL:-}" ] && { echo "Could not connect to Xymon daemon@$1" >&2; exit 5; }
case $2 in
xymondboard*)
	# What xymond kept: the colour sent, unless XYMONDROP says it kept
	# nothing, as for a host hosts.cfg does not name.
	printf '%s\n' "$2" >> "$WORK/asked"
	[ -n "${XYMONDROP:-}" ] || sed -n '1s/^status+[^ ]* [^ ]* \([a-z]*\) .*/\1/p' "$WORK/sent" ;;
*) printf '%s\n' "$2" > "$WORK/sent" ;;
esac
SH
cat > "$bin/gh" <<'SH'
#!/bin/sh
echo ran >> "$WORK/gh.ran"
exec sleep 60
SH
cat > "$bin/curl" <<'SH'
#!/bin/sh
[ "${CURL:-}" = fail ] && { echo "curl: (6) Could not resolve host" >&2; exit 6; }
for a; do u=$a; done
case $u in *page=1) ;; *) echo '[]'; exit 0 ;; esac
printf '['; sep=; while read -r t; do printf '%s{"tag_name": "%s"}' "$sep" "$t"; sep=,; done < "$WORK/tags"; printf ']\n'
SH
# shellcheck disable=SC2016 # expanded by the stand-in
printf '#!/bin/sh\necho "$1" >> "$WORK/slept"\n' > "$bin/sleep"
chmod 755 "$bin/xymon" "$bin/gh" "$bin/curl" "$bin/sleep"
export WORK=$work
# report [REPORTER] -- the reporter run as xymonlaunch runs it.
report() {
	RC=0; rm -f "$work/sent"
	PATH="$bin:$PATH" XYMON="$bin/xymon" XYMSRV=0.0.0.0 XYMONHOME="$home" MACHINEDOTS=srv.example.com \
		XYMON_PLUGINS_WAIT="${WAIT:-0}" "${1:-$ext/xymon-plugin-report.sh}" >"$work/log" 2>&1 || RC=$?
}
sent() { cat "$work/sent" 2>/dev/null || :; }

printf 'xymon-plugin/v%s\n' "$want" > "$work/tags"
report
assert_equal 0 "$RC" "[S33] the reporter ends with 0: $(cat "$work/log")"
assert_contains "status+31h srv,example,com.plugins green " "$(first_line "$(sent)")" "[S33] every plugin up to date: green, valid 31 hours, for this host"
assert_contains "xymon-plugin: $want installed; up to date" "$(sent)" "[S33] with outdated's lines"
assert_contains "sent green" "$(cat "$work/log")" "and the log says so"

printf 'xymon-plugin/v99.0.0\n' > "$work/tags"
report
assert_contains "srv,example,com.plugins yellow " "$(first_line "$(sent)")" "[S33] a newer release published: yellow"
assert_contains "99.0.0 released" "$(sent)" "naming it"

printf 'xymon-plugin/v%s\n' "$want" > "$work/tags"
mv "$ext/VERSION" "$work/VERSION"
report
assert_contains "srv,example,com.plugins yellow " "$(first_line "$(sent)")" "[S33] a VERSION that cannot be compared: yellow"
assert_contains "is missing" "$(sent)" "saying why"
mv "$work/VERSION" "$ext/VERSION"

CURL=fail report
assert_equal 0 "$RC" "[S33] GitHub not reached: the reporter still ends with 0"
[ -e "$work/sent" ] && fail "[S33] GitHub not reached, and a status was sent: $(sent)"
assert_contains "nothing sent" "$(cat "$work/log")" "[S33] the log says nothing was sent, and why"
assert_contains "Could not resolve host" "$(cat "$work/log")" "with curl's words"

# Another status: yellow, saying so -- here an installer beside a copy of
# the reporter that ends with 2.
mkdir -p "$work/odd"
cp "$ext/xymon-plugin-report.sh" "$work/odd/"
printf '#!/bin/sh\necho "usage: ./xymon-plugin ..." >&2\nexit 2\n' > "$work/odd/xymon-plugin"; chmod 755 "$work/odd/xymon-plugin"
report "$work/odd/xymon-plugin-report.sh"
assert_contains "srv,example,com.plugins yellow " "$(first_line "$(sent)")" "[S33] another status of outdated: yellow"
assert_contains "outdated ended with 2" "$(sent)" "saying it"

XYMONFAIL=1 report
assert_equal 1 "$RC" "[S33] a status that could not be sent ends the reporter with 1"
assert_contains "could not send green to 0.0.0.0" "$(cat "$work/log")" "and the log says so"

# MACHINEDOTS names the host, the server's name in xymonserver.cfg, the one
# hosts.cfg knows: not MACHINE, which may be the system's name instead, as
# with Homebrew's Xymon (localhost against bcs-Mac-mini,local).
RC=0; PATH="$bin:$PATH" XYMON="$bin/xymon" XYMSRV=0.0.0.0 XYMONHOME="$home" MACHINEDOTS=localhost MACHINE=bcs-Mac-mini,local \
	XYMON_PLUGINS_WAIT=0 "$ext/xymon-plugin-report.sh" >"$work/log" 2>&1 || RC=$?
assert_contains "status+31h localhost.plugins green " "$(first_line "$(sent)")" "[S33] MACHINEDOTS names the host, not MACHINE"
assert_contains "xymondboard host=localhost test=plugins" "$(cat "$work/asked")" "[S33] and the status is read back for it"

# A status xymond does not keep -- a host hosts.cfg does not name -- is
# said, and ends the reporter with 1: xymon itself ends with 0 then.
XYMONDROP=1 report
assert_equal 1 "$RC" "[S33] a status xymond did not keep ends the reporter with 1"
assert_contains "which xymond did not keep: is srv.example.com in hosts.cfg?" "$(cat "$work/log")" "[S33] and the log says so"
assert_equal 0 "$(grep -c '; sent green$' "$work/log" || true)" "and does not say it was sent"

# The wait: drawn up to XYMON_PLUGINS_WAIT seconds, each run.
rm -f "$work/slept"
for _ in 1 2 3 4 5 6; do WAIT=40 report; done
[ -s "$work/slept" ] || fail "[S33] the reporter never waited"
while read -r s; do
	if [ "$s" -lt 1 ] || [ "$s" -gt 40 ]; then fail "[S33] a wait of $s seconds, outside 1-40"; fi
done < "$work/slept"

# gh, which may hang, was never run: what it starts the task's MAXTIME
# could not stop.
[ -e "$work/gh.ran" ] && fail "[S33] the reporter ran gh, which no time bounds"

# Without the server's environment it says what is missing, and sends
# nothing.
RC=0; env -u XYMON PATH="$bin:$PATH" XYMSRV=0.0.0.0 XYMONHOME="$home" MACHINEDOTS=srv.example.com \
	"$ext/xymon-plugin-report.sh" >"$work/log" 2>&1 || RC=$?
assert_equal 1 "$RC" "without XYMON: 1"
assert_contains "XYMON is not set" "$(cat "$work/log")" "saying what is missing"

# An update of a plugin whose task is on never leaves tasks.d/'s link
# pointing nowhere: xymonlaunch, reading tasks.d/ then, would drop the task
# and stop it, and not notice the file back. Every rm, mv, cp, ln, mkdir
# the update runs checks the link before and after itself.
watch=$work/watch; mkdir -p "$watch"
for c in rm mv cp ln mkdir; do
	cat > "$watch/$c" <<'SH'
#!/bin/sh
c=${0##*/}
[ -e "$LINK" ] || printf 'before %s %s\n' "$c" "$*" >> "$WORK/dangling"
"/bin/$c" "$@"; rc=$?
[ -e "$LINK" ] || printf 'after %s %s\n' "$c" "$*" >> "$WORK/dangling"
exit $rc
SH
	chmod 755 "$watch/$c"
done
rm -f "$work/dangling"
link=$home/etc/tasks.d/xymon-plugin.cfg
PATH="$watch:$PATH" LINK="$link" WORK="$work" "$ROOT/xymon-plugin" update --server xymon-plugin XYMONHOME="$home" MANDIR="$work/man" >"$work/update.log" 2>&1 \
	|| fail "update --server xymon-plugin failed: $(tail -n 5 "$work/update.log")"
[ -s "$work/dangling" ] && fail "[S13] during the update, tasks.d/'s link pointed nowhere: $(head -n 3 "$work/dangling")"
[ "$(readlink "$link")" = "$home/ext/xymon-plugin/tasks.cfg" ] || fail "[S13] the update did not leave the task on"
assert_contains "task is on, as it was" "$(cat "$work/update.log")" "[S13] and says so"
# The same when this version's task file differs from the one installed,
# unedited: it replaces it.
for f in "$ext/tasks.cfg" "$ext/.shipped/tasks.cfg"; do printf '# an older version\n' >> "$f"; done
rm -f "$work/dangling"
PATH="$watch:$PATH" LINK="$link" WORK="$work" "$ROOT/xymon-plugin" update --server xymon-plugin XYMONHOME="$home" MANDIR="$work/man" >"$work/update.log" 2>&1 \
	|| fail "update --server xymon-plugin failed: $(tail -n 5 "$work/update.log")"
assert_contains "unedited, is replaced by this version's" "$(cat "$work/update.log")" "[S7] an unedited task file takes this version's"
[ -s "$work/dangling" ] && fail "[S13] replacing the task file, tasks.d/'s link pointed nowhere: $(head -n 3 "$work/dangling")"
[ "$(readlink "$link")" = "$home/ext/xymon-plugin/tasks.cfg" ] || fail "[S13] the update did not leave the task on"
grep -q 'an older version' "$ext/tasks.cfg" && fail "[S7] the older task file stayed"
# And where tasks.d/ holds a copy of the task file, not a link, as an older
# install made, or an editor writing by renaming left: it becomes the link.
rm -f "$link" && cp "$ext/tasks.cfg" "$link"
rm -f "$work/dangling"
PATH="$watch:$PATH" LINK="$link" WORK="$work" "$ROOT/xymon-plugin" update --server xymon-plugin XYMONHOME="$home" MANDIR="$work/man" >"$work/update.log" 2>&1 \
	|| fail "update --server xymon-plugin failed: $(tail -n 5 "$work/update.log")"
[ -s "$work/dangling" ] && fail "[S13] making a copy in tasks.d/ the link, it was absent: $(head -n 3 "$work/dangling")"
[ "$(readlink "$link")" = "$home/ext/xymon-plugin/tasks.cfg" ] || fail "[S13] the copy in tasks.d/ did not become the link"
for f in "$home/etc/tasks.d"/.*.tmp; do [ -e "$f" ] || [ -L "$f" ] && fail "a temporary name stayed in tasks.d/: $f"; done

pass "the plugins column's task is installed off and enabled; its reporter sends green, yellow, or nothing when GitHub is not reached, valid 31 hours, after a wait drawn at random"
