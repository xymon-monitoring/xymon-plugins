#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-connect.sh
#
# xymonapi-connect, as ./install.sh install-tools lays it out, connects a machine to
# the API: it reads a user and a password holding a space, a quote, a
# backslash and a glob character, gets the API to take them as they are, and
# keeps the token it gets for this machine's short hostname -- mode 600, not
# the password -- and prints the settings a client needs. Run again, it keeps
# a token that works and replaces a revoked one; a wrong password is said; a
# Ctrl-C at its password prompt ends it with echo back on and no token; it
# says when the API and the client run different versions, and who can act;
# and a certificate it does not trust is said before anything is asked.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), Apache's htpasswd,
# curl and openssl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"
command -v openssl >/dev/null 2>&1 || skip "openssl is not installed"

work=$(mktempdir)
server_tree "$work/inst"
register_cleanup 'stop_process "$API_PID"'

# The API as ./install.sh install-server lays it out, its VERSION the client's, and the
# client as ./install.sh install-tools does.
"$ROOT/install.sh" install xymonapi XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "install.sh install-server failed: $(tail -n 5 "$work/install.log")"
"$ROOT/install.sh" install-tools xymonapi PREFIX="$work/client" >"$work/client.log" 2>&1 \
	|| fail "install.sh install-tools failed: $(tail -n 5 "$work/client.log")"
connect=$work/client/bin/xymonapi-connect
assert_file_exists "$connect"
mine=$(cat "$work/client/libexec/xymon-plugins/xymonapi/VERSION")
apiver=$work/inst/ext/xymonapi/VERSION
printf '%s\n' "$mine" > "$apiver"
API_ROOT=$work/inst/ext/xymonapi

hard='pa ss"wo\rd*'
htpasswd -cbB "$work/htpasswd" carol "$hard" 2>/dev/null || fail "htpasswd could not add carol"
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/tokens/tokens"
start_api
url=http://127.0.0.1:$API_PORT
cfg=$work/cfg
tok=$cfg/xymon-api/xymon.token

# run [ARG...] -- xymonapi-connect URL with this test's configuration
# directory; stdout in $work/out, stderr in $work/err, its status in rc.
# Its input is redirected from a file, never piped: a pipeline would run it
# in a subshell, and rc would not come back.
run() {
	rc=0
	XDG_CONFIG_HOME="$cfg" HOME="$work" "$connect" "$url" "$@" > "$work/out" 2> "$work/err" || rc=$?
}

# A password file an earlier setup kept: it goes.
mkdir -p "$cfg/xymon-api"
printf '%s\n' "$hard" > "$cfg/xymon-api/xymon.password"
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
[ "$rc" -eq 0 ] || fail "xymonapi-connect failed with $rc: $(cat "$work/err")"
assert_file_exists "$tok"
assert_match '^xat_' "$(cat "$tok")" "it keeps a token, the API having taken carol's password as it is"
assert_equal "-rw-------" "$(ls -l "$tok" | cut -c1-10)" "readable by this user alone"
assert_not_contains "$hard" "$(cat "$tok")" "the token is not the password"
[ -e "$cfg/xymon-api/xymon.password" ] && fail "the old password file was left"
assert_contains "XYMONAPI_URL=$url" "$(cat "$work/out")" "it prints the API's address"
assert_contains "XYMONAPI_TOKEN_FILE=$tok" "$(cat "$work/out")" "and the token file"
assert_not_contains "XYMONAPI_CA" "$(cat "$work/out")" "and no certificate, over http"
assert_not_contains "differ" "$(cat "$work/err")" "the same version on both sides is not remarked on"
assert_not_contains "runs xymonapi" "$(cat "$work/err")" "nor said at all"
h=$(hostname)
assert_contains "\"client\":\"${h%%.*}\"" "$(curl -s -u "carol:$hard" "$url/xymon/api/v1/tokens")" "the token is for this machine's short name"

# Again: the token works, so it is kept and nothing is asked.
first=$(cat "$tok")
run < /dev/null
[ "$rc" -eq 0 ] || fail "a second run failed with $rc: $(cat "$work/err")"
assert_equal "$first" "$(cat "$tok")" "a token that works is kept"
assert_not_contains "password for" "$(cat "$work/err")" "and no password asked"

# Revoked on the server: a new one, with the password asked again.
curl -s -o /dev/null -u "carol:$hard" -X DELETE "$url/xymon/api/v1/tokens/${h%%.*}"
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
[ "$rc" -eq 0 ] || fail "a run after revoking failed with $rc: $(cat "$work/err")"
[ "$first" != "$(cat "$tok")" ] || fail "a revoked token was kept"
assert_match '^xat_' "$(cat "$tok")" "a revoked token is replaced"

# A wrong password: said, and nothing written.
curl -s -o /dev/null -u "carol:$hard" -X DELETE "$url/xymon/api/v1/tokens/${h%%.*}"
second=$(cat "$tok")
printf 'carol\nwrong\n' > "$work/in"; run < "$work/in"
assert_equal "1" "$rc" "a wrong password fails"
assert_contains "refused the password for carol" "$(cat "$work/err")" "and says so"
assert_equal "$second" "$(cat "$tok")" "and writes no token"

# The versions: an older API is the server admin's to update, an older
# client this machine's. The token above is revoked: a fresh one first.
# The API reads its version when it starts: each is a restart with another
# VERSION beside it, and the tokens file, with the token, stays.
api_at() {
	printf '%s\n' "$1" > "$apiver"
	stop_process "$API_PID"; API_PID=""
	start_api
	url=http://127.0.0.1:$API_PORT
}
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
api_at 0.0.1
run < /dev/null
assert_contains "the API runs xymonapi 0.0.1, this machine's client $mine: the server's admin" "$(cat "$work/err")" "an older API: the server's admin updates it"
api_at 99.0.0
run < /dev/null
assert_contains "the API runs xymonapi 99.0.0, this machine's client $mine: update here" "$(cat "$work/err")" "an older client: this machine updates"
api_at "$mine"

# A Ctrl-C at the password prompt, on a terminal: echo back on, no token.
# No virtualenv and no XYMONAPI_PYTHON: the python3 on PATH runs it, and the
# password is the first thing asked -- no question about a virtualenv.
mkdir -p "$work/cfg2"
rc=0
out=$(XDG_CONFIG_HOME="$work/cfg2" HOME="$work" XYMONAPI_USER=carol XYMONAPI_PYTHON="" \
	"${XYMONAPI_PYTHON:-python3}" "$ROOT/tests/lib/ctrl-c.py" 'password for carol: ' "$connect" "$url" 2>&1) || rc=$?
assert_equal "130" "$rc" "Ctrl-C at the password prompt ends it ($out)"
assert_contains "echo on" "$out" "with echo back on"
assert_not_contains "Traceback" "$out" "and no traceback on the terminal"
[ -e "$work/cfg2/xymon-api/xymon.token" ] && fail "a token was kept after Ctrl-C"
stop_process "$API_PID"; API_PID=""

# A certificate this machine does not trust: said first, with where to copy
# it, before a user or password is asked; copied there, it is used.
mkdir -p "$work/tls"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=xymon-test" \
	-addext "subjectAltName=IP:127.0.0.1" \
	-keyout "$work/tls/xymond.key" -out "$work/tls/xymond.pem" > /dev/null 2>&1 \
	|| fail "openssl could not make a certificate"
chmod 600 "$work/tls/xymond.key"
XYMONAPI_PASSWD="" XYMONAPI_TLS_CERT="$work/tls/xymond.pem" XYMONAPI_TLS_KEY="$work/tls/xymond.key" start_api
url=https://127.0.0.1:$API_PORT
cfg=$work/cfg3
mkdir -p "$cfg/xymon-api"
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
assert_equal "1" "$rc" "an untrusted certificate stops it"
assert_contains "copy the server's certificate, or the CA that signed it, to $cfg/xymon-api/xymon-ca.pem" "$(cat "$work/err")" "saying where to copy it"
assert_not_contains "password" "$(cat "$work/err")" "before a password is asked"
assert_not_contains "user:" "$(cat "$work/err")" "or a user"
cp "$work/tls/xymond.pem" "$cfg/xymon-api/xymon-ca.pem"
run < /dev/null
[ "$rc" -eq 0 ] || fail "with the certificate copied, it failed with $rc: $(cat "$work/err")"
assert_contains "XYMONAPI_CA=$cfg/xymon-api/xymon-ca.pem" "$(cat "$work/out")" "the copied certificate is used, and printed"
assert_not_contains "XYMONAPI_TOKEN_FILE" "$(cat "$work/out")" "an API that asks no password needs no token"

pass "xymonapi-connect gets this machine a token with a password typed once, keeps it while it works, says a wrong password, a version difference and an untrusted certificate, and stops cleanly on Ctrl-C"
