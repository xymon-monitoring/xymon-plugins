#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/clientage/tests/clientage-client.sh
#
# clientage's client part: installed off in a client's tree, its task the
# script with the two thresholds, its log in @LOGDIR@; the script sends
# the host's status clientage from the age of the clock the Xymon client
# wrote in its last message against logfetch --clock now: green under the
# first threshold, yellow under the second, red beyond, yellow with no
# message yet or no clock; thresholds that are not numbers, and a send
# that fails, end it with 1. Xymon is never reached: logfetch and xymon
# are stand-ins.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
work=$(cd "$work" && pwd -P)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME" "$work/man"

# A client's tree, its clientlaunch.cfg reading clientlaunch.d/.
c=$work/client
mkdir -p "$c/bin" "$c/etc" "$c/ext" "$c/tmp"
: > "$c/bin/xymonclient.sh"; : > "$c/etc/xymonclient.cfg"
printf 'optional directory %s/etc/clientlaunch.d\n' "$c" > "$c/etc/clientlaunch.cfg"

rc=0; out=$("$ROOT/xymon-plugin" install --client clientage XYMONHOME="$c" MANDIR="$work/man" </dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "install --client clientage failed ($rc): $out"
tf=$c/ext/clientage/tasks.cfg
assert_contains "[clientage-client]" "$(cat "$tf")" "[S6] its task named after its part"
assert_contains "CMD $c/ext/clientage/clientage-client.sh 15 30" "$(cat "$tf")" "the task runs the script with its two thresholds"
assert_contains "ENVFILE $c/etc/xymonclient.cfg" "$(cat "$tf")" "under the client's environment"
assert_contains "LOGFILE \$XYMONCLIENTLOGS/clientage-client.log" "$(cat "$tf")" "[S6] its log in the client's logs"
{ [ -e "$c/etc/clientlaunch.d/clientage-client.cfg" ] || [ -L "$c/etc/clientlaunch.d/clientage-client.cfg" ]; } && fail "[S5] installed on"

# The stand-ins: logfetch --clock prints NOW as Xymon's does; xymon keeps
# the status sent, or fails with XYMONFAIL.
cat > "$c/bin/logfetch" <<'SH'
#!/bin/sh
[ "$1" = --clock ] || exit 1
[ -n "${NOW:-}" ] || exit 0
printf 'epoch: %s.123456\nlocal: x\nUTC: x\n' "$NOW"
SH
cat > "$work/xymon" <<'SH'
#!/bin/sh
[ -n "${XYMONFAIL:-}" ] && { echo "Could not connect" >&2; exit 5; }
printf '%s %s\n' "$1" "$2" > "$WORK/sent"
SH
chmod 755 "$c/bin/logfetch" "$work/xymon"
export WORK=$work
now=2000000000
# message AGO -- a client message whose clock is AGO seconds before now.
message() { printf '[date]\nx\n[clock]\nepoch: %s.000001\nlocal: x\n[uptime]\nx\n' "$((now - $1))" > "$c/tmp/msg.host.example.com.txt"; }
# run [ARG...] -- the script as its task runs it.
run() {
	rc=0; rm -f "$work/sent"
	out=$(env XYMON="$work/xymon" XYMSRV=192.0.2.1 XYMONHOME="$c" XYMONTMP="$c/tmp" MACHINEDOTS=host.example.com \
		NOW="${NOW-$now}" "$c/ext/clientage/clientage-client.sh" "$@" 2>&1) || rc=$?
}
sent() { cat "$work/sent" 2>/dev/null || :; }

message 300; run 15 30
assert_equal 0 "$rc" "a message 5 minutes old: ends with 0: $out"
assert_contains "192.0.2.1 status host,example,com.clientage green " "$(sent)" "5 minutes old: green, for this host, to its server"
assert_contains "is 5 minutes old (yellow from 15, red from 30)" "$(sent)" "and says the age and the thresholds"
message 1200; run 15 30
assert_contains "clientage yellow " "$(sent)" "20 minutes old: yellow"
message 2400; run 15 30
assert_contains "clientage red " "$(sent)" "40 minutes old: red"
message 2400; run 45 60
assert_contains "clientage green " "$(sent)" "the thresholds given are the ones used"
rm -f "$c/tmp/msg.host.example.com.txt"; run 15 30
assert_contains "clientage yellow " "$(sent)" "no message yet: yellow, not red"
assert_contains "no message of the client yet" "$(sent)" "and says so"
message 300; NOW='' run 15 30
assert_contains "clientage yellow " "$(sent)" "no clock: yellow"
message 300; run 15 thirty
assert_equal 1 "$rc" "thresholds that are not numbers end it with 1"
[ -z "$(sent)" ] || fail "and nothing was sent: $(sent)"
message 300; XYMONFAIL=1 run 15 30
assert_equal 1 "$rc" "a send that fails ends it with 1"
assert_contains "not sent to 192.0.2.1" "$out" "and its log says so"

pass "clientage's client part: installed off, its task the script with two thresholds and its log in @LOGDIR@; green, yellow, red by the age of the client's last message against logfetch --clock, yellow with no message or no clock; bad thresholds and a failed send end it with 1"
