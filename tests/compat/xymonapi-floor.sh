#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-floor.sh
#
# The client plugins name the oldest xymonapi they work with -- the floor --
# in their PLUGIN files, and xymonapi_client.py, which both read the API
# through, repeats it: the three agree. Installed as ./install.sh install-tools lays them
# out, against an API older than the floor, the MCP server says so with each
# answer and on stderr, and xymonapi-rag on stderr; against one at or past
# it, neither says anything.
#
# Skips where the API or the MCP server cannot run (tests/lib/xymonapi.sh).
# Needs the xymon client of the Xymon tree in XYMON_SRC (for a free port),
# Apache's htpasswd and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"

work=$(mktempdir)
server_tree "$work/inst"
register_cleanup 'stop_process "$API_PID"'
htpasswd -cbB "$work/htpasswd" alice secret 2>/dev/null

# The API as ./install.sh install-server lays it out, with a release's VERSION beside it,
# so that /health has one to give and the script one to install.
"$ROOT/install.sh" install-server XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "install.sh install-server failed: $(tail -n 5 "$work/install.log")"
version=xymonapi/v9.9.9
printf '%s\n' "$version" > "$work/inst/ext/xymonapi/VERSION"
API_ROOT=$work/inst/ext/xymonapi

export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/tokens/tokens"
start_api
# The API reads its version when it starts: each is a restart with another
# VERSION beside it, and the tokens file, with the token, stays.
api_at() {
	printf '%s\n' "$1" > "$work/inst/ext/xymonapi/VERSION"
	stop_process "$API_PID"; API_PID=""
	start_api
}

"$ROOT/install.sh" install-tools PREFIX="$work/client" >"$work/client.log" 2>&1 \
	|| fail "install.sh install-tools failed: $(tail -n 5 "$work/client.log")"
assert_file_exists "$work/client/libexec/xymon-plugins/xymonapi-mcp/VERSION"
floor=$(sed -n 's/^requires: xymonapi >= \([0-9.]*\).*/\1/p' "$ROOT/plugins/xymonapi-mcp/PLUGIN")
[ -n "$floor" ] || fail "xymonapi-mcp's PLUGIN names no xymonapi version it needs"
assert_contains "API_FLOOR = \"$floor\"" "$(cat "$ROOT/plugins/xymonapi/xymonapi_client.py")" "xymonapi_client.py repeats the floor of its PLUGIN file"
assert_contains "xymonapi >= $floor" "$(cat "$ROOT/plugins/xymonapi-rag/PLUGIN")" "and xymonapi-rag, which reads the API through it, names the same floor"
api_at xymonapi/v0.0.1
mine=$(curl -s -u alice:secret -X POST -H 'Content-Type: application/json' -d '{"client":"mcptest"}' "http://127.0.0.1:$API_PORT/xymon/api/v1/tokens" \
	| sed -n 's/.*"token": *"\(xat_[A-Za-z0-9_-]*\)".*/\1/p')
[ -n "$mine" ] || fail "the API gave alice no token"
XYMONAPI_TOKEN="$mine" MCP_ROOT="$work/client/libexec/xymon-plugins" \
	mcp "http://127.0.0.1:$API_PORT" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health","arguments":{}}}' || true
answer=$(grep '"id":3' "$work/mcp.out") || fail "no answer to the health call: $(tail -n 5 "$work/mcp.err")"
assert_contains 'alive' "$answer" "the MCP server's health tool gives /health's answer"
assert_contains "is xymonapi xymonapi/v0.0.1; this client needs $floor or later" "$answer" "and says the API is older than the client needs"
assert_contains "this client needs $floor" "$(cat "$work/mcp.err")" "and on stderr"
api_at "$version"
XYMONAPI_TOKEN="$mine" MCP_ROOT="$work/client/libexec/xymon-plugins" \
	mcp "http://127.0.0.1:$API_PORT" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health","arguments":{}}}' || true
answer=$(grep '"id":3' "$work/mcp.out") || fail "no answer to the health call: $(tail -n 5 "$work/mcp.err")"
assert_not_contains 'warning' "$answer" "an API past the floor: no warning"
# xymonapi-rag reads the API through the same xymonapi_client.py: with no index here
# its search asks the API, and an old API is said on stderr before that.
api_at xymonapi/v0.0.1
XYMONAPI_URL="http://127.0.0.1:$API_PORT" XYMONAPI_TOKEN="$mine" XYMONAPI_RAG_INDEX="$work/none.npz" \
	"$work/client/libexec/xymon-plugins/xymonapi-rag/xymonapi-rag.sh" search -k 1 'anything' > /dev/null 2> "$work/rag.err" || true
assert_contains "this client needs $floor" "$(cat "$work/rag.err")" "xymonapi-rag says on stderr when the API is older than it needs"
api_at "$version"
XYMONAPI_URL="http://127.0.0.1:$API_PORT" XYMONAPI_TOKEN="$mine" XYMONAPI_RAG_INDEX="$work/none.npz" \
	"$work/client/libexec/xymon-plugins/xymonapi-rag/xymonapi-rag.sh" search -k 1 'anything' > /dev/null 2> "$work/rag.err" || true
assert_not_contains 'this client needs' "$(cat "$work/rag.err")" "and nothing when it is not"

pass "the floor agrees in both PLUGIN files and xymonapi_client.py, and an API below it is said by xymonapi-mcp and xymonapi-rag, one at or past it is not"
