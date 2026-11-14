#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-plugins.sh
#
# What ./install.sh install-server stages on a server is what /plugins gives, and a machine
# installs from it: the archive holds each plugin installed there, laid out
# as the repository is but for the tests, with install.sh and LICENSE;
# ./install.sh install-tools xymonapi-mcp there installs the MCP
# server, xymonapi's client and xymonapi-connect, at the server's versions.
# A plugin uninstalled from the server leaves the archive, and xymonapi is
# not uninstalled while one staged there needs it.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), curl and tar.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)
server_tree "$work/inst"
register_cleanup 'stop_process "$API_PID"'

# Every server-side plugin, as an admin installs them.
"$ROOT/install.sh" install-server XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "install.sh install-server failed: $(tail -n 5 "$work/install.log")"
# The MCP server and the agent are beside the API too, for its /ask.
for p in xymonapi-mcp xymonapi-agent; do
	[ -x "$work/inst/ext/$p/$p.sh" ] || fail "install.sh install-server did not put $p beside the API, for /ask"
done
API_ROOT=$work/inst/ext/xymonapi
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD=""
start_api
plugins=http://127.0.0.1:$API_PORT/xymon/api/v1/plugins

curl -s -o "$work/plugins.tgz" "$plugins"
# The path's name before xymonapi 2.0.0 is gone, not served twice: where
# /plugins has an archive to give, /client is a path like any unknown one.
assert_equal "404" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API_PORT/xymon/api/v1/client")" "[C2] /client is gone"
tar -tzf "$work/plugins.tgz" > "$work/list" || fail "/plugins' answer is not a gzipped tar"
for f in install.sh LICENSE plugins/xymonapi/PLUGIN plugins/xymonapi-mcp/PLUGIN plugins/xymonapi-rag/PLUGIN \
         plugins/xymonapi/xymonapi_client.py plugins/xymonapi-mcp/server.py; do
	grep -qx "xymon-plugins/$f" "$work/list" || fail "the archive has no $f: $(head -n 20 "$work/list")"
done
t=$(grep '/tests/' "$work/list" || true)
[ -n "$t" ] && fail "the archive holds tests: $(first_line "$t")"
grep -q '__pycache__' "$work/list" && fail "the archive holds __pycache__"

# A machine installs the MCP server from it, as its README says, with no
# make: one stands first on PATH that records being called and fails.
mkdir -p "$work/nomake"
printf '#!/bin/sh\necho "make $*" >> "%s/make.called"\nexit 99\n' "$work" > "$work/nomake/make"
chmod 755 "$work/nomake/make"
mkdir -p "$work/laptop"
tar -xzf "$work/plugins.tgz" -C "$work/laptop"
PATH="$work/nomake:$PATH" "$work/laptop/xymon-plugins/install.sh" install-tools xymonapi-mcp PREFIX="$work/prefix" >"$work/client.log" 2>&1 \
	|| fail "install.sh install-tools from the archive failed: $(tail -n 5 "$work/client.log")"
[ -e "$work/make.called" ] && fail "installing from the archive ran make: $(cat "$work/make.called")"
for c in xymonapi-mcp xymonapi-connect; do
	[ -x "$work/prefix/bin/$c" ] || fail "installing from the archive gave no $c"
done
assert_equal "$(cat "$work/inst/ext/xymonapi/VERSION")" "$(cat "$work/prefix/libexec/xymon-plugins/xymonapi/VERSION")" \
	"the client installed from the archive is the server's version"
assert_equal "$(sed -n 's/^version: *//p' "$ROOT/plugins/xymonapi-mcp/PLUGIN")" "$(cat "$work/prefix/libexec/xymon-plugins/xymonapi-mcp/VERSION")" \
	"and so is the MCP server"

# Uninstalled from the server, a plugin leaves the archive; xymonapi stays
# while one staged needs it.
"$ROOT/install.sh" uninstall-server xymonapi-rag XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/un.log" 2>&1 \
	|| fail "install.sh uninstall-server of xymonapi-rag failed: $(tail -n 5 "$work/un.log")"
tar -tzf <(curl -s "$plugins") > "$work/list2"
grep -q '^xymon-plugins/plugins/xymonapi-rag/' "$work/list2" && fail "an uninstalled plugin stayed in the archive"
grep -q '^xymon-plugins/plugins/xymonapi-mcp/PLUGIN$' "$work/list2" || fail "and took the others with it"
rc=0
"$ROOT/install.sh" uninstall-server xymonapi XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/un2.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "xymonapi was uninstalled while the staged MCP server needs it"
assert_contains "needed by xymonapi-mcp" "$(cat "$work/un2.log")" "and the refusal names it"

pass "/plugins gives the plugins installed on the server, without their tests, and a machine installs the MCP server from it at the server's versions; an uninstalled plugin leaves it"
