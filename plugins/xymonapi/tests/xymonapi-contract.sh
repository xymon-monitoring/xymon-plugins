#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-contract.sh
#
# Every failure the API can answer is one of the errors openapi.yaml lists,
# with the status that goes with it: one request per kind of failure -- a
# parameter that is not a name, no RRD file, xymond not answering, a path
# that is not the API's, a method a path does not take, no user where one is
# asked -- and each answer's status and error are the expected ones, and
# the error is in the spec's closed list. /plugins answers without a user
# even where every other path asks for one. Every answer carries an
# X-Request-Id: the client's when it is a valid one, the API's otherwise,
# and a failure's is in the API's log.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), curl, and Apache's
# htpasswd for the part with a password.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'
mkdir -p "$work/rrd"

# The closed list, as the spec writes it: enum: [a, b, ...] under Error.
spec="$ROOT/plugins/xymonapi/openapi.yaml"
errors=$(sed -n '/^    Error:/,/^    [A-Z]/p' "$spec" | sed -n 's/.*enum: *\[\([^]]*\)\].*/\1/p' | tr -d ' ')
[ -n "$errors" ] || fail "openapi.yaml lists no closed set of errors under Error"

# answer RULE METHOD PATH STATUS ERROR [CURL ARGS...] -- the answer to METHOD
# PATH has STATUS, and its error is ERROR, one of the spec's (C1), with an
# X-Request-Id (C5); RULE, as [Cn], is the rule of openapi.yaml the case is
# about, said in each message.
answer() {
	local rule=$1 method=$2 path=$3 status=$4 error=$5 body code got; shift 5
	body=$work/body
	code=$(curl -s --max-time 30 -D "$work/headers" -o "$body" -w '%{http_code}' -X "$method" "$@" "http://127.0.0.1:$API_PORT$path")
	assert_equal "$status" "$code" "$rule [C1] $method $path: the status"
	grep -qi '^x-request-id: [A-Za-z0-9._-]' "$work/headers" || fail "$rule [C5] $method $path: no X-Request-Id in the answer"
	got=$(sed -n 's/.*"error": *"\([a-z_]*\)".*/\1/p' "$body")
	assert_equal "$error" "$got" "$rule [C1] $method $path: the error ($(b=$(cat "$body"); printf '%s' "${b:0:200}"))"
	case ",$errors," in
		*",$got,"*) ;;
		*) fail "$rule [C1] $method $path: error '$got' is not in openapi.yaml's list ($errors)" ;;
	esac
}

export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONRRDS="$work/rrd"
XYMONAPI_PASSWD="" start_api
v1=/xymon/api/v1
answer '[C1]' GET "$v1/status?entity=not%20a%20name&test=conn" 400 bad_request
answer '[C1]' GET "$v1/series?entity=host.example.com&test=la" 404 not_found
answer '[C1]' GET "$v1/alarms" 502 upstream
answer '[C2]' GET "$v1/no-such-path" 404 not_found
answer '[C2]' GET "/elsewhere" 404 not_found
answer '[C2]' DELETE "$v1/alarms" 405 method_not_allowed
answer '[C2]' POST "$v1/health" 405 method_not_allowed

# rid HEADER-VALUE PATH -- the X-Request-Id the answer to PATH carries.
rid() {
	curl -s --max-time 30 -D - -o /dev/null -H "X-Request-Id: $1" "http://127.0.0.1:$API_PORT$2" \
		| tr -d '\r' | sed -n 's/^[Xx]-[Rr]equest-[Ii]d: //p'
}
assert_equal "laptop-7.call_42" "$(rid laptop-7.call_42 "$v1/health")" "[C5] a valid X-Request-Id from the client comes back"
got=$(rid 'not valid!' "$v1/health")
[ -n "$got" ] && [ "$got" != 'not valid!' ] || fail "[C5] an invalid X-Request-Id was not replaced: '$got'"
rid trace-me-0042 "$v1/no-such-path" > /dev/null
grep -q 'trace-me-0042.*answered 404' "$work/api.log" || fail "[C5] the failure is not in the log with its id: $(tail -n 3 "$work/api.log")"
stop_process "$API_PID"; API_PID=""

# With a password asked: no user is unauthorized, everywhere but /plugins.
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"
htpasswd -cbB "$work/htpasswd" alice secret 2>/dev/null
XYMONAPI_PASSWD="$work/htpasswd" XYMONAPI_TOKENS="$work/tokens" start_api
answer '[C3]' GET "$v1/alarms" 401 unauthorized
answer '[C3]' GET "$v1/no-such-path" 401 unauthorized
answer '[C3]' GET "$v1/alarms" 502 upstream -u alice:secret
# /plugins answers without a user: here, run from the repository with
# nothing staged, that nothing is staged, not that a user is missing.
answer '[C4]' GET "$v1/plugins" 404 not_found
assert_contains "./install.sh install there stages it" "$(curl -s "http://127.0.0.1:$API_PORT$v1/plugins")" "and what to do about it"

pass "every failure is an error openapi.yaml lists, with its status, every answer an X-Request-Id, and /plugins needs no user"
