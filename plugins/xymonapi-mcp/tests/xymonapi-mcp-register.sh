#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi-mcp/tests/xymonapi-mcp-register.sh
#
# xymonapi-mcp register, as ./install.sh install lays it out, connects this
# machine to the API through xymonapi-connect -- a password asked once, a
# token kept -- and registers the MCP server with Claude Code and Codex: the
# installed launcher as the command, with the API's address and the token
# file; XYMONAPI_PYTHON only when it is set; the certificate only when one
# is used. It leaves a virtualenv beside the plugins alone; where a client
# is not installed, prints the command to run later; and where one fails,
# says which, registers the other all the same, and exits 1.
#
# claude and codex are stubs that record their arguments. Skips where the API
# cannot run (tests/lib/xymonapi.sh). Needs the xymon client of the Xymon
# tree in XYMON_SRC (for a free port), and Apache's htpasswd.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'

"$ROOT/install.sh" install xymonapi-mcp PREFIX="$work/client" >"$work/client.log" 2>&1 \
	|| fail "install.sh install failed: $(tail -n 5 "$work/client.log")"
mcp_bin=$work/client/bin/xymonapi-mcp
launcher=$work/client/libexec/xymon-plugins/xymonapi-mcp/xymonapi-mcp.sh

htpasswd -cbB "$work/htpasswd" carol secret 2>/dev/null
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/tokens/tokens"
start_api
url=http://127.0.0.1:$API_PORT

mkdir -p "$work/stub"
for c in claude codex; do
	printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/%s.args"\n' "$work" "$c" > "$work/stub/$c"
	chmod 755 "$work/stub/$c"
done
py=$(command -v "${XYMONAPI_PYTHON:-python3}")
# A PATH with the stubs and the system's tools, and no real claude or codex.
# The test's Python goes in with the stubs: on FreeBSD, for one, it lives in
# /usr/local/bin, beside whatever else is installed there.
ln -s "$py" "$work/stub/python3"
path="$work/stub:/usr/bin:/bin"

# A virtualenv beside the plugins, as ./install.sh venv makes one: left as it
# is, since the launchers run with it (tests/compat/xymonapi-python.sh).
mkdir -p "$work/client/libexec/xymon-plugins/venv/bin"
printf 'carol\nsecret\n' > "$work/in"
rc=0
out=$(XDG_CONFIG_HOME="$work/cfg" HOME="$work" PATH="$path" XYMONAPI_PYTHON="" \
	"$mcp_bin" register "$url" < "$work/in" 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "register failed with $rc: $out"
tok=$work/cfg/xymon-api/xymon.token
assert_match '^xat_' "$(cat "$tok")" "register connects this machine: a token is kept"
for c in claude codex; do
	args=$(cat "$work/$c.args")
	assert_contains "XYMONAPI_URL=$url" "$args" "$c is given the API's address"
	assert_contains "XYMONAPI_TOKEN_FILE=$tok" "$args" "and the token file"
	assert_contains "$launcher" "$args" "and the installed launcher as the command"
	assert_not_contains "XYMONAPI_PYTHON" "$args" "and no XYMONAPI_PYTHON, unset"
	assert_not_contains "XYMONAPI_CA" "$args" "and no certificate, over http"
	assert_not_contains "secret" "$args" "and never the password"
done
assert_contains "--scope" "$(cat "$work/claude.args")" "Claude Code at user scope"
assert_file_exists "$work/client/libexec/xymon-plugins/venv/bin"
assert_not_contains "removed" "$out" "the virtualenv beside the plugins is left alone"

# Again, with XYMONAPI_PYTHON set: passed on. The token works: nothing asked.
: > "$work/claude.args"; : > "$work/codex.args"
rc=0
out=$(XDG_CONFIG_HOME="$work/cfg" HOME="$work" PATH="$path" XYMONAPI_PYTHON="$py" \
	"$mcp_bin" register "$url" < /dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "a second register failed with $rc: $out"
assert_contains "XYMONAPI_PYTHON=$py" "$(cat "$work/claude.args")" "XYMONAPI_PYTHON set: Claude Code is given it"
assert_contains "XYMONAPI_PYTHON=$py" "$(cat "$work/codex.args")" "and Codex"
assert_not_contains "password for" "$out" "a working token: nothing asked"

# Codex not installed: the command to run later is printed.
rm "$work/stub/codex"; : > "$work/claude.args"
rc=0
out=$(XDG_CONFIG_HOME="$work/cfg" HOME="$work" PATH="$path" XYMONAPI_PYTHON="" \
	"$mcp_bin" register "$url" < /dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "register without codex failed with $rc: $out"
assert_contains "codex is not here; to register xymon with it later:" "$out" "a client not installed is said"
assert_contains "codex mcp add xymon --env XYMONAPI_URL=$url" "$out" "with the command to run"
assert_contains "XYMONAPI_URL=$url" "$(cat "$work/claude.args")" "and the other is registered"

# Codex installed but failing: said by name, with the command, and Claude
# Code is still registered; the exit code says one failed.
printf '#!/bin/sh\necho "codex: broken" >&2; exit 3\n' > "$work/stub/codex"; chmod 755 "$work/stub/codex"
: > "$work/claude.args"
rc=0
out=$(XDG_CONFIG_HOME="$work/cfg" HOME="$work" PATH="$path" XYMONAPI_PYTHON="" \
	"$mcp_bin" register "$url" < /dev/null 2>&1) || rc=$?
assert_equal "1" "$rc" "register fails when a client's registration fails"
assert_contains "could not register xymon with codex, which exited 3:" "$out" "and says which client, by name"
assert_contains "codex mcp add xymon --env XYMONAPI_URL=$url" "$out" "with the command that failed"
assert_contains "XYMONAPI_URL=$url" "$(cat "$work/claude.args")" "and the other client is registered all the same"
rm "$work/stub/codex"

# A refused password: nothing registered.
: > "$work/claude.args"
printf 'carol\nwrong\n' > "$work/in"
rc=0
out=$(XDG_CONFIG_HOME="$work/cfg2" HOME="$work" PATH="$path" XYMONAPI_PYTHON="" \
	"$mcp_bin" register "$url" < "$work/in" 2>&1) || rc=$?
assert_equal "1" "$rc" "register fails when the API refuses the password"
assert_equal "" "$(cat "$work/claude.args")" "and registers nothing"

# --help asks for the usage, and is not a URL to connect to.
: > "$work/claude.args"
rc=0
out=$(XDG_CONFIG_HOME="$work/cfg" HOME="$work" PATH="$path" XYMONAPI_PYTHON="" \
	"$mcp_bin" register --help < /dev/null 2>&1) || rc=$?
assert_equal "0" "$rc" "register --help exits 0"
assert_equal "usage: xymonapi-mcp register URL [NAME]" "$out" "and prints register's usage, not xymonapi-connect's"
assert_equal "" "$(cat "$work/claude.args")" "and registers nothing"

pass "xymonapi-mcp register connects this machine and registers the installed server with Claude Code and Codex, with the token file and XYMONAPI_PYTHON only when set"
