#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-auth.sh
#
# With XYMONAPI_PASSWD naming an htpasswd file, the API answers only a user
# and password that file holds, and 401 with a WWW-Authenticate challenge to
# anything else. Both formats Apache's htpasswd writes are accepted: $apr1$,
# its default and what Xymon's useradm and chpasswd create, and bcrypt. Every
# path is covered, /openapi.json and FastAPI's /docs included. A user
# name that looks like an option is refused, not passed to htpasswd as one.
# A password file the API cannot read stops it from starting. /plugins alone
# is open: it gives the code of the plugins staged here, an archive rooted
# at xymon-plugins/, with no password or tokens file in it; /health gives
# the version, to a user, and only fields the spec lists. Installing from
# that archive is tests/compat/xymonapi-plugins.sh's.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), Apache's htpasswd
# and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'

htpasswd -cb "$work/htpasswd" alice secret 2>/dev/null
htpasswd -bB "$work/htpasswd" bob s3cret 2>/dev/null
grep -q '^alice:\$apr1\$' "$work/htpasswd" || fail "htpasswd did not write alice in its \$apr1\$ format"
grep -q '^bob:\$2y\$' "$work/htpasswd" || fail "htpasswd did not write bob as bcrypt"

# The API as ./install.sh install-server lays it out, with a release's VERSION beside it,
# so that /health has one to give and the script one to install.
"$ROOT/install.sh" install XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "install.sh install-server failed: $(tail -n 5 "$work/install.log")"
version=xymonapi/v9.9.9
printf '%s\n' "$version" > "$work/inst/ext/xymonapi/VERSION"
API_ROOT=$work/inst/ext/xymonapi

# The answers checked here need no xymond: /health says alive:false without
# one, and the password is checked first, on every path but /plugins.
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/tokens/tokens"
start_api

url="http://127.0.0.1:$API_PORT/xymon/api/v1/health"
code() { curl -s -o /dev/null -w '%{http_code}' "$@" "$url"; }

rc=0
assert_equal "401" "$(code)" "[C3] no user and password"
# Header names are case-insensitive, and uvicorn sends them in lower case.
assert_contains 'www-authenticate: basic realm="xymon"' "$(curl -s -D - -o /dev/null "$url" | tr -d '\r' | tr 'A-Z' 'a-z')" "the 401 asks for Basic authentication"
assert_equal "200" "$(code -u alice:secret)" "alice, \$apr1\$, right password"
assert_equal "200" "$(code -H "Authorization: basic $(printf 'alice:secret' | base64)")" "the scheme spelt basic, in lower case"
assert_equal "401" "$(code -u alice:wrong)" "[C3] alice, wrong password"
assert_equal "200" "$(code -u bob:s3cret)" "bob, bcrypt, right password"
assert_equal "401" "$(code -u carol:secret)" "[C3] a user the file does not hold"
assert_equal "401" "$(code -u -b:secret)" "a user name that looks like an option"

# FastAPI serves these beside the API's own paths; a password covers them too.
for path in /openapi.json /docs; do
	assert_equal "401" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API_PORT$path")" "[C3] $path without a user"
	assert_equal "200" "$(curl -s -o /dev/null -w '%{http_code}' -u alice:secret "http://127.0.0.1:$API_PORT$path")" "$path with a user"
done

# /plugins: open, a password set or not, since what it gives is the plugins'
# code, as the repository has it: no user, password, token or setting.
assert_equal "200" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API_PORT/xymon/api/v1/plugins")" "[C4] /plugins without a user"
curl -s -o "$work/plugins.tgz" "http://127.0.0.1:$API_PORT/xymon/api/v1/plugins"
mkdir -p "$work/unpacked"
tar -xzf "$work/plugins.tgz" -C "$work/unpacked" || fail "/plugins' answer is not a gzipped tar"
assert_equal "xymon-plugins" "$(ls "$work/unpacked")" "rooted at xymon-plugins/"
grep -rqF "$(first_line "$(cut -d: -f2 "$work/htpasswd")")" "$work/unpacked" && fail "[C4] /plugins gave the password file's contents"
[ -n "$(find "$work/unpacked" -type f -name tokens)" ] && fail "[C4] /plugins gave a tokens file"
assert_contains "\"version\":\"$version\"" "$(curl -s -u alice:secret "$url")" "/health gives the version to a user"
# The process names its directory in its command line, which is what a
# restart finds it by: pkill -f "$XYMONHOME/ext/xymonapi/".
grep -qx "$API_PID" <<<"$(pgrep -f "$work/inst/ext/xymonapi/" || true)" \
	|| fail "pgrep -f on the API's directory does not find it, so the documented pkill would not stop it: $(ps -o command= -p "$API_PID")"
# An install over it stops it, saying so, since it would go on with the
# code it loaded; xymonlaunch, not run here, would start the new. With
# DESTDIR, a package's staging, nothing runs from there: it is left alone.
"$ROOT/install.sh" install xymonapi XYMONHOME="$work/inst" MANDIR="$work/man" DESTDIR="$work/stage" >"$work/stage.log" 2>&1 \
	|| fail "install.sh install-server with DESTDIR failed: $(tail -n 5 "$work/stage.log")"
kill -0 "$API_PID" 2>/dev/null || fail "an install with DESTDIR stopped the running API"
assert_not_contains "Stopped" "$(cat "$work/stage.log")" "and says nothing of it"
rc=0
"$ROOT/install.sh" install xymonapi XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/reinstall.log" 2>&1 || rc=$?
assert_equal "0" "$rc" "an install over a running API succeeds, not stopping itself ($(tail -n 3 "$work/reinstall.log"))"
assert_contains "Stopped the API that ran the old code (PID $API_PID)" "$(cat "$work/reinstall.log")" "and stops the API, saying which"
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$API_PID" 2>/dev/null || break; sleep 0.5; done
kill -0 "$API_PID" 2>/dev/null && fail "the API still runs after an install over it"
API_PID=""
printf '%s\n' "$version" > "$work/inst/ext/xymonapi/VERSION"   # the test's own, which the install replaced
start_api
url="http://127.0.0.1:$API_PORT/xymon/api/v1/health"
assert_not_contains "$version" "$(curl -s "$url")" "and not to a stranger"
# The version of the code that runs: an install the API was not restarted
# for, which writes a new VERSION beside it, does not change it.
printf 'xymonapi/v9.9.10\n' > "$work/inst/ext/xymonapi/VERSION"
assert_contains "\"version\":\"$version\"" "$(curl -s -u alice:secret "$url")" "/health keeps the version the process started with"
printf '%s\n' "$version" > "$work/inst/ext/xymonapi/VERSION"
# Every field /health gives is one the spec lists for it: a field renamed in
# the code and not in openapi.yaml is a contract the API does not keep.
spec_fields=$(sed -n '/^    Health:/,/^    [A-Z]/p' "$ROOT/plugins/xymonapi/openapi.yaml" | sed -n 's/^        \([a-z_]*\):.*/\1/p')
for f in $(curl -s -u alice:secret "$url" | "${XYMONAPI_PYTHON:-python3}" -c 'import json, sys; print(" ".join(json.load(sys.stdin)))'); do
	grep -qx "$f" <<<"$spec_fields" || fail "/health gives \"$f\", which openapi.yaml's Health does not list ($(echo $spec_fields))"
done

# Xymon's own password file is the default: with XYMONHOME set and
# etc/xymonpasswd there, nothing else need be set, and the API asks for
# what the web pages ask for. The empty string turns it off; with neither,
# the API does not start.
stop_process "$API_PID"
API_PID=""
mkdir -p "$work/home/etc"; cp "$work/htpasswd" "$work/home/etc/xymonpasswd"
unset XYMONAPI_PASSWD
XYMONHOME="$work/home" start_api
url="http://127.0.0.1:$API_PORT/xymon/api/v1/health"
assert_equal "401" "$(code)" "with XYMONHOME's etc/xymonpasswd and no setting, a password is asked"
assert_equal "200" "$(code -u alice:secret)" "the web pages' user is let in"
stop_process "$API_PID"
API_PID=""
XYMONHOME="$work/home" XYMONAPI_PASSWD="" start_api
url="http://127.0.0.1:$API_PORT/xymon/api/v1/health"
assert_equal "200" "$(code)" "XYMONAPI_PASSWD set empty: no password asked"
stop_process "$API_PID"
API_PID=""
# With nothing set and no etc/xymonpasswd, the API does not start, rather
# than answer anyone: an open API is asked for, never had by a file that
# went missing.
rm "$work/home/etc/xymonpasswd"
rc=0
( unset XYMONAPI_PASSWD; XYMONHOME="$work/home" XYMONAPI_LISTEN="127.0.0.1:$(free_port)" \
	"$ROOT/plugins/xymonapi/xymonapi.sh" ) > "$work/nopasswd.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "the API with no setting and no etc/xymonpasswd"
assert_contains "XYMONAPI_PASSWD is not set, and Xymon's password file" "$(cat "$work/nopasswd.log")" "and it says why"
assert_contains "set XYMONAPI_PASSWD empty" "$(cat "$work/nopasswd.log")" "and how to open it on purpose"
rc=0
XYMONAPI_PASSWD="$work/no-such-file" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/nofile.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "the API with a password file it cannot read"
assert_contains "cannot read XYMONAPI_PASSWD" "$(cat "$work/nofile.log")" "and it says why"

pass "XYMONAPI_PASSWD lets in only the users and passwords of its htpasswd file, in either format"
