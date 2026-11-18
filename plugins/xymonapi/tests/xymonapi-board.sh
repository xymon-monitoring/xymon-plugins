#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-board.sh
#
# The API reports the board a running xymond holds: a status sent to xymond
# comes back from /states with its colour turned into a verdict, a red one is
# listed in /alarms and a green one is not, a state says when it is
# acknowledged, and /health names the xymond it asked. An operation the API
# does not implement answers 404 rather than sample data.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs a built Xymon
# server tree in XYMON_SRC, and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMOND "$XYMON_SRC/xymond/xymond"
require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)

# shellcheck disable=SC2034 # read by xymond-daemon.sh and the cleanup
XYMOND_PID=""
register_cleanup 'stop_process "$API_PID" "$XYMOND_PID"'

printf 'page test Test\n127.0.0.1 red.example.com # conn\n127.0.0.1 green.example.com # conn\n127.0.0.1 disk.example.com # disk\n127.0.0.1 dis.example.com # conn\n127.0.0.1 disk2.example.com # disk\n127.0.0.1 enc.example.com # conn\n127.0.0.1 lt.example.com # conn\n127.0.0.1 enc2.example.com # procs\n127.0.0.1 crit.example.com # conn\n127.0.0.1 critold.example.com # conn\n127.0.0.1 clr.example.com # conn\n' > "$work/hosts.cfg"

mkdir -p "$work/home/etc" "$work/home/tmp" "$work/home/www"
require_cfg XYMONSERVER_CFG "$XYMON_SRC/xymond/etcfiles/xymonserver.cfg"
sed -e 's|^XYMONHOME=.*|XYMONHOME="'"$work"'/home"|' \
    -e 's|^XYMONTMP=.*|XYMONTMP="'"$work"'/home/tmp"|' \
	"$XYMONSERVER_CFG" > "$work/xymonserver.cfg"

xymond_launch() {
	local port=$1; shift
	"$XYMOND" --no-daemon --listen="127.0.0.1:$port" \
		--hosts="$work/hosts.cfg" --env="$work/xymonserver.cfg" \
		--pidfile="$work/xymond.pid" --checkpoint-file="$work/chk.out" \
		"$@" \
		> "$work/xymond.log" 2>&1 &
	# shellcheck disable=SC2034 # read by xymond-daemon.sh and the cleanup
	XYMOND_PID=$!
}

start_xymond

send() { "$XYMONCLIENT" "127.0.0.1:$PORT" "$1" || fail "xymond rejected: $1"; }
send "status red,example,com.conn red down"
send "status green,example,com.conn green up"
send "status disk,example,com.disk yellow Filesystems NOT ok
/var at 91% - 2.1G of 24G free
/boot ok"
# An acknowledgement names the status by the cookie xymond gave it.
sleep 0.4
cookie=$("$XYMONCLIENT" "127.0.0.1:$PORT" "xymondboard host=disk.example.com test=disk fields=cookie")
[ -n "$cookie" ] || fail "xymond gave the yellow status no cookie"
send "xymondack $cookie 60 cleaning old kernels, back in an hour"
send "status dis,example,com.conn red down"
send "disable dis,example,com.conn 7200 maintenance window"
# A host whose name begins with another's, with a status of its own.
send "status disk2,example,com.disk green Filesystems all ok"
send "status clr,example,com.conn clear no data"
# Characters xymondboard encodes on its way out: | tab \ and a literal \n.
send "status enc,example,com.conn green C:\\temp | cpu	load \\n not a newline"
# A lifetime with a unit and a group, both legal on the command line.
send "status+5h/group:ops lt,example,com.conn green up for 5h"
# An acknowledgement that has already run out: 0 minutes.
cookie=$("$XYMONCLIENT" "127.0.0.1:$PORT" "xymondboard host=red.example.com test=conn fields=cookie")
[ -n "$cookie" ] || fail "xymond gave the red status no cookie"
send "xymondack $cookie 0 already over"
# Acknowledged from the critical-systems view: ackinfo puts it in acklist,
# HOST.TEST, level, seconds, who and words on lines of their own
# (web/ackinfo.c), and leaves acktime at 0. One for an hour; one for a
# second, which has run out by the time it is asked for.
send "status crit,example,com.conn red down"
send "status critold,example,com.conn red down"
send "ackinfo crit.example.com.conn
1
3600
alice
on it from the critical view"
send "ackinfo critold.example.com.conn
1
1
bob
was on it"
sleep 1.2

# A status with a secret in it, as a process list shows a command line.
send "status enc2,example,com.procs green up
root  1234  mysqld --password=hunter2 --port=3306
Token: abc"
sleep 0.4

# XYMONAPI_HIDE: what its expressions match is [hidden] in every text.
printf '# secrets on command lines\npassword=\\S+\n\nToken: \\w+\n' > "$work/hide"
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:$PORT" XYMONAPI_HIDE="$work/hide"
start_api

health=$(api_get /health)
assert_contains '"xymond":{"alive":true' "$health" "/health while xymond runs"
assert_contains '"answer":"xymond' "$health" "/health gives the xymond it asked, as it answered"
assert_contains '"api":{"version":' "$health" "/health gives the API's version under api"

red=$(api_get '/states?entity=red.example.com&test=conn')
assert_contains '"id":"red.example.com:conn"' "$red" "/states for the red host"
assert_contains '"verdict":"critical"' "$red" "a red status is a critical verdict"

green=$(api_get '/states?entity=green.example.com&test=conn')
assert_contains '"verdict":"ok"' "$green" "a green status is an ok verdict"

# /states says when a state is acknowledged, in the same shape as /status:
# a page drawing the board picks its icon by it. Both ways, xymondack's
# acktime and the critical-systems view's acklist, running and run out.
acked=$(api_get '/states?entity=disk.example.com&test=disk')
assert_contains '"acknowledged":{"until":"' "$acked" "/states gives an acknowledgement made with xymondack, with its end time"
assert_contains 'cleaning old kernels' "$acked" "and its words"
crit=$(api_get '/states?entity=crit.example.com&test=conn')
assert_contains '"acknowledged":{"until":"' "$crit" "/states gives one from the critical-systems view, in acklist alone"
assert_contains 'on it from the critical view' "$crit" "with its words"
assert_not_contains '"acknowledged"' "$red" "an acknowledgement with xymondack that ran out is not given, though xymond still carries it"
assert_not_contains '"acknowledged"' "$(api_get '/states?entity=critold.example.com&test=conn')" "nor one in acklist that ran out"
assert_not_contains '"acknowledged"' "$green" "a state nobody acknowledged has none"
assert_not_contains '"acknowledged"' "$(api_get '/states?entity=dis.example.com&test=conn')" "nor has a disabled one, whose verdict says it"
ack_st=$(api_get '/status?entity=disk.example.com&test=disk')
ack_st=${ack_st#*\"acknowledged\":}; ack_st=${ack_st%%\}*}
assert_contains "$ack_st" "$acked" "/states and /status give the same acknowledgement"

alarms=$(api_get /alarms)
assert_contains '"id":"red.example.com:conn"' "$alarms" "a red status is an alarm"
assert_not_contains 'green.example.com' "$alarms" "a green status is not an alarm"
alarm() { a=${alarms#*\"id\":\"$1\"}; printf '%s' "${a%%\}*}"; }
assert_contains '"severity":"major","status":"firing"' "$(alarm red.example.com:conn)" "red: major, firing"
assert_contains '"severity":"minor"' "$(alarm disk.example.com:disk)" "yellow: minor"
assert_contains '"severity":"indeterminate","status":"firing"' "$(alarm clr.example.com:conn)" "clear, no data: indeterminate (X.733)"
assert_contains '"severity":"indeterminate","status":"suppressed"' "$(alarm dis.example.com:conn)" "blue, disabled: indeterminate, suppressed (as Alertmanager)"

# /status: the text behind a colour, with what was done about it.
st=$(api_get '/status?entity=disk.example.com&test=disk')
assert_contains '"verdict":"warning"' "$st" "/status gives the verdict"
assert_contains '"text":"Filesystems NOT ok' "$st" "and the status text, without the command line that set it"
assert_contains '/var at 91%' "$st" "newlines unescaped"
assert_contains '2.1G of 24G free\n/boot ok' "$st" "line by line"
assert_contains '"acknowledged":{' "$st" "an acknowledged status says so"
assert_contains 'cleaning old kernels' "$st" "with the acknowledgement's words"
assert_not_contains '"disabled"' "$st" "and is not disabled"
dis=$(api_get '/status?entity=dis.example.com&test=conn')
assert_contains '"disabled":{' "$dis" "a disabled test says so"
assert_contains 'maintenance window' "$dis" "with the reason given"
assert_contains '"verdict":"disabled"' "$dis" "and its verdict is disabled, as the board shows it blue"
assert_equal "404" "$(api_code '/status?entity=green.example.com&test=disk')" "/status of a test the host has not"
# xymondboard matches host= and test= as unanchored regular expressions;
# the API must not pass on another host's status as this one's.
assert_contains '"text":"Filesystems NOT ok' "$(api_get '/status?entity=disk.example.com&test=disk')" "disk.example.com gets its own text, not disk2's"
assert_contains '"text":"Filesystems all ok"' "$(api_get '/status?entity=disk2.example.com&test=disk')" "and disk2.example.com its own"
assert_equal "404" "$(api_code '/status?entity=disk.example&test=disk')" "a host name that is the start of a real one"
assert_equal "404" "$(api_code '/status?entity=disk.example.com&test=dis')" "a test name that is the start of a real one"
assert_equal "404" "$(api_code '/status?entity=d.sk.example.com&test=disk')" "a dot is a dot, not any character"
enc=$(api_get '/status?entity=enc.example.com&test=conn')
assert_contains '"text":"C:\\temp | cpu\tload \\n not a newline"' "$enc" "a pipe, a tab, a backslash and a literal \\n are decoded as xymondboard encoded them"
assert_contains '"text":"up for 5h"' "$(api_get '/status?entity=lt.example.com&test=conn')" "the command line is left out when it has a lifetime with a unit and a group"
assert_not_contains '"acknowledged"' "$(api_get '/status?entity=red.example.com&test=conn')" "an acknowledgement that ran out is not reported, though xymond still carries it"
crit=$(api_get '/status?entity=crit.example.com&test=conn')
assert_contains '"acknowledged":{' "$crit" "an acknowledgement from the critical-systems view, in acklist alone, says so"
assert_contains 'on it from the critical view' "$crit" "with its words"
assert_not_contains '"acknowledged"' "$(api_get '/status?entity=critold.example.com&test=conn')" "one in acklist that ran out is not reported"
assert_equal "400" "$(api_code '/status?entity=../etc&test=disk')" "/status with a host name that is a path"

hid=$(api_get '/status?entity=enc2.example.com&test=procs')
assert_contains 'mysqld --[hidden] --port=3306' "$hid" "XYMONAPI_HIDE blanks a password on a command line"
assert_contains '[hidden]' "$hid" "and a token"
assert_not_contains 'hunter2' "$hid" "the password is gone"
assert_not_contains 'abc' "$hid" "and so is the token"
assert_contains 'Filesystems NOT ok' "$(api_get '/status?entity=disk.example.com&test=disk')" "other texts are untouched"
assert_contains 'cleaning old kernels' "$(api_get '/status?entity=disk.example.com&test=disk')" "an acknowledgement too"
# A file of expressions that is not one stops the API: silently hiding
# nothing would be worse.
stop_process "$API_PID"; API_PID=""
printf 'password=(\n' > "$work/badhide"
rc=0
XYMONAPI_HIDE="$work/badhide" XYMONAPI_LISTEN="127.0.0.1:$API_PORT" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/badhide.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "the API with an expression that is not one"
assert_contains 'XYMONAPI_HIDE' "$(cat "$work/badhide.log")" "and says which setting"
assert_contains 'line 1' "$(cat "$work/badhide.log")" "and which line"
rc=0
XYMONAPI_HIDE="$work/no-such-file" XYMONAPI_LISTEN="127.0.0.1:$API_PORT" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/nohide.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "the API with a hide file it cannot read"
assert_contains 'cannot read XYMONAPI_HIDE' "$(cat "$work/nohide.log")" "and says so"
unset XYMONAPI_HIDE
start_api

assert_equal "404" "$(api_code /views)" "an operation the API does not implement"

pass "the API reports xymond's board: states, verdicts, alarms, one status with its text and acknowledgement, and health"
