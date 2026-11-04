#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-dialogue.sh
#
# ./install.sh with no action on a terminal asks: install or remove, which
# role this machine plays, which plugins; Enter takes each default -- the
# role XYMONHOME detects, every plugin of it -- and the answers run the
# action they spell, said first. A plugin chosen alone brings what it
# needs, named; a plugin removed takes its installed dependents, named,
# and only installed plugins are offered for a removal. Without a
# terminal, no action is the usage, and nothing is installed.
#
# Installed into a scratch directory. The API is copied, not run; the
# dialogue is driven on a pseudo-terminal by tests/lib/answer.py, which
# needs the Python the plugins need anyway. PYTHON names a stub that lacks
# every module, so that a plugin needing modules always ends with the venv
# offer, answered N here: the offer is tested in xymonapi-python.sh.

set -euo pipefail
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
py=${XYMONAPI_PYTHON:-python3}
command -v "$py" >/dev/null 2>&1 || skip "no $py to drive a pseudo-terminal with"
mkdir -p "$work/lacks"
printf '#!/bin/sh\ncase "$*" in *"print("*) echo "fastembed numpy" ;; *find_spec*) exit 1 ;; esac\nexit 0\n' > "$work/lacks/python3"
chmod 755 "$work/lacks/python3"
lacks=PYTHON=$work/lacks/python3

# Without a terminal, no action is the usage, settings or not.
rc=0
"$ROOT/install.sh" PREFIX="$work/none" </dev/null >"$work/none.log" 2>&1 || rc=$?
assert_equal "2" "$rc" "install.sh with no action and no terminal exits with the usage"
assert_contains "usage: ./install.sh" "$(cat "$work/none.log")" "and prints it"
[ -e "$work/none" ] && fail "install.sh with no action installed something"

# Your own machine, defaults all the way: every tools plugin.
prefix=$work/tools
rc=0
"$py" "$ROOT/tests/lib/answer.py" 'Install or remove? [install]' '' 'Role [2]' '' 'Plugins [' '' '[y/N] ' 'N' \
	-- "$ROOT/install.sh" PREFIX="$prefix" "$lacks" >"$work/all.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "the dialogue installing everything failed with $rc: $(tail -n 5 "$work/all.log")"
assert_contains "Which role does this machine play?" "$(cat "$work/all.log")" "the dialogue asks the role"
assert_contains "2. your own machine: the plugins' commands, under $prefix" "$(cat "$work/all.log")" "naming PREFIX"
assert_contains "Running: ./install.sh install" "$(cat "$work/all.log")" "and says the action the answers spell"
for p in xymonapi xymonapi-mcp xymonapi-rag xymonapi-agent; do
	assert_file_exists "$prefix/libexec/xymon-plugins/$p/VERSION"
done

# One plugin named brings what it needs, and says so.
prefix=$work/one
rc=0
"$py" "$ROOT/tests/lib/answer.py" 'Install or remove? [install]' '' 'Role [2]' '' 'Plugins [' 'xymonapi-mcp' \
	-- "$ROOT/install.sh" PREFIX="$prefix" "$lacks" >"$work/one.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "the dialogue installing xymonapi-mcp failed with $rc: $(tail -n 5 "$work/one.log")"
assert_contains "With xymonapi, which xymonapi-mcp needs." "$(cat "$work/one.log")" "a plugin chosen alone names what it brings"
assert_contains "Running: ./install.sh install xymonapi-mcp xymonapi" "$(cat "$work/one.log")" "and the action runs both"
assert_file_exists "$prefix/libexec/xymon-plugins/xymonapi/VERSION"
assert_file_exists "$prefix/libexec/xymon-plugins/xymonapi-mcp/VERSION"
[ -e "$prefix/libexec/xymon-plugins/xymonapi-rag" ] && fail "a plugin not chosen was installed"

# Removing: only what is installed is offered, and a plugin removed takes
# the installed plugins that need it.
rc=0
"$py" "$ROOT/tests/lib/answer.py" 'Install or remove? [install]' 'remove' 'Role [2]' '' 'Plugins [' 'xymonapi' \
	-- "$ROOT/install.sh" PREFIX="$prefix" "$lacks" >"$work/remove.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "the dialogue removing xymonapi failed with $rc: $(tail -n 5 "$work/remove.log")"
assert_contains "Plugins [xymonapi xymonapi-mcp]" "$(cat "$work/remove.log")" "a removal offers the installed plugins only"
assert_contains "With xymonapi-mcp, installed here, which needs xymonapi." "$(cat "$work/remove.log")" "and names the dependent it takes along"
assert_contains "Running: ./install.sh remove xymonapi xymonapi-mcp" "$(cat "$work/remove.log")" "then runs the removal"
[ -e "$prefix/libexec/xymon-plugins/xymonapi" ] && fail "xymonapi stayed after the dialogue removed it"
[ -e "$prefix/libexec/xymon-plugins/xymonapi-mcp" ] && fail "xymonapi-mcp stayed after the dialogue removed what it needs"

# The Xymon server, detected from XYMONHOME: the role defaults to 1.
home=$work/server
rc=0
"$py" "$ROOT/tests/lib/answer.py" 'Install or remove? [install]' '' 'Role [1]' '' 'Plugins [' 'xymonapi' '[y/N] ' 'N' \
	-- "$ROOT/install.sh" XYMONHOME="$home" MANDIR="$work/man" "$lacks" >"$work/server.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "the dialogue installing on the server failed with $rc: $(tail -n 5 "$work/server.log")"
assert_contains "1. the Xymon server: the plugins' tasks and the API, under $home/ext" "$(cat "$work/server.log")" "with XYMONHOME set, the server role is offered first"
assert_contains "Running: XYMONHOME=$home ./install.sh install xymonapi" "$(cat "$work/server.log")" "and the action is the server's"
assert_file_exists "$home/ext/xymonapi/VERSION"
assert_file_exists "$home/etc/tasks.d/xymonapi"

pass "./install.sh with no action on a terminal asks install or remove, the role XYMONHOME detects, and the plugins, runs the action the answers spell and says it, brings what a plugin needs and takes what needs a removed one; without a terminal it is the usage"
