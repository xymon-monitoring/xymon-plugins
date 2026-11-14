#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-python.sh
#
# Which Python a launcher runs with, on either side: XYMONAPI_PYTHON when it
# is set; else the virtualenv beside the installed plugins, venv/; else the
# python3 on PATH, without a word: none of them asks. The same
# order in xymonapi-mcp, xymonapi-rag and xymonapi-connect, which exec the
# Python they chose on their own module.
# How the virtualenv comes to be: an install that needs modules makes it from
# the Python PYTHON= names when that one has them, with --system-site-packages
# and fetching nothing; says which Python ./install.sh venv-server would use when none has;
# and says which modules a virtualenv already there lacks. On a terminal --
# tests/lib/answer.py gives the install one -- those two hints are offers:
# "y" makes the virtualenv, or completes it, with ./install.sh venv-tools; "N"
# leaves the hint. Without a terminal nothing is asked. ./install.sh venv-tools
# makes it with PYTHON, and leaves one that is there alone. A command whose
# module is missing says what installs it.
#
# The search for a Python when PYTHON= is not given is not run: what it
# finds depends on the machine.
# Needs a Python 3.9 or later with the venv module in
# XYMONAPI_PYTHON, or python3.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
server_tree "$work/server"
real=${XYMONAPI_PYTHON:-python3}
command -v "$real" >/dev/null 2>&1 || skip "$real is not installed"

# Two Pythons that are not: one passing every check, as one that has the
# modules would, recording who ran it and with what; one failing the module
# check alone, as one without them would.
fake() { # DIR NAME
	mkdir -p "$1"
	# Never through a link: a venv's python3 is one, to the interpreter
	# itself, and writing through it would replace that interpreter.
	rm -f "$1/python3"
	printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/python.log"\nexit 0\n' "$2" "$work" > "$1/python3"
	chmod 755 "$1/python3"
}
fake "$work/has" has
mkdir -p "$work/lacks"
# Asked which modules are missing, it names them all; asked whether any is,
# it says yes.
printf '#!/bin/sh\ncase "$*" in *"print("*) echo "fastembed numpy" ;; *find_spec*) exit 1 ;; esac\nexit 0\n' > "$work/lacks/python3"
chmod 755 "$work/lacks/python3"

# The three client-side plugins, as ./install.sh install-tools lays them out, on a
# machine whose Python lacks the modules: no virtualenv is made, and the
# install says what ./install.sh venv-server would use.
prefix=$work/prefix
lib=$prefix/libexec/xymon-plugins
for p in xymonapi-mcp xymonapi-rag; do
	"$ROOT/install.sh" install-tools "$p" PREFIX="$prefix" PYTHON="$work/lacks/python3" >"$work/install-$p.log" 2>&1 \
		|| fail "install.sh install-tools of $p failed: $(tail -n 5 "$work/install-$p.log")"
done
[ -e "$lib/venv" ] && fail "a virtualenv was made with no Python that has the modules"
assert_contains "no Python with the modules this plugin needs (fastembed numpy): ./install.sh venv-tools PYTHON=$work/lacks/python3" \
	"$(cat "$work/install-xymonapi-rag.log")" "installing a plugin that needs modules, with none that has them, names the Python ./install.sh venv-tools would use"
assert_not_contains "[y/N]" "$(cat "$work/install-xymonapi-rag.log")" "and, with no terminal, asks nothing"
assert_not_contains "virtualenv" "$(cat "$work/install-xymonapi-mcp.log")" "a plugin that needs no modules says nothing of it"
# On the server the hint names the server's command, not the client's.
"$ROOT/install.sh" install xymonapi XYMONHOME="$work/server" MANDIR="$work/man" PYTHON="$work/lacks/python3" >"$work/install-server.log" 2>&1 \
	|| fail "install.sh install-server of xymonapi failed: $(tail -n 5 "$work/install-server.log")"
assert_contains "(fastapi uvicorn yaml): ./install.sh venv-server PYTHON=$work/lacks/python3" \
	"$(cat "$work/install-server.log")" "installing on the server names ./install.sh venv-server"

fake "$lib/venv/bin" venv
fake "$work/path" path
fake "$work/named" named
run() { # LAUNCHER ARGS... -- stdin is no terminal, so nothing is asked.
	# XYMONAPI_PYTHON is PY, or unset: the suite's own setting must not
	# decide the test.
	: > "$work/python.log"; : > "$work/err"
	[ -x "$prefix/bin/$1" ] || fail "no launcher $prefix/bin/$1"
	XYMONAPI_PYTHON="${PY:-}" PATH="$work/path:$PATH" "$prefix/bin/$@" < /dev/null > /dev/null 2> "$work/err" || true
}

# The virtualenv beside the plugins, before the python3 on PATH, silently.
for cmd in "xymonapi-mcp" "xymonapi-rag search x" "xymonapi-connect http://127.0.0.1:1"; do
	# shellcheck disable=SC2086 # the command's words are meant to split
	run $cmd
	case $cmd in
		xymonapi-mcp) module=xymonapi-mcp/server.py ;;
		xymonapi-rag*) module=xymonapi-rag/xymonrag.py ;;
		*) module=xymonapi/xymonapi_client.py ;;
	esac
	assert_contains "venv $lib/$module" "$(cat "$work/python.log")" "${cmd%% *} runs its module with the virtualenv beside the plugins"
	assert_not_contains "path " "$(cat "$work/python.log")" "and does not consult the python3 on PATH"
	assert_equal "" "$(cat "$work/err")" "with nothing said"
done

# XYMONAPI_PYTHON names another: that one, and the virtualenv is left out.
PY="$work/named/python3" run xymonapi-mcp
assert_contains "named $lib/xymonapi-mcp/server.py" "$(cat "$work/python.log")" "XYMONAPI_PYTHON wins over the virtualenv"
assert_not_contains "venv " "$(cat "$work/python.log")" "which is not run"

# No virtualenv: the python3 on PATH, and not a word, from any of them.
rm -rf "$lib/venv"
for cmd in "xymonapi-mcp" "xymonapi-rag search x" "xymonapi-connect http://127.0.0.1:1"; do
	# shellcheck disable=SC2086 # the command's words are meant to split
	run $cmd
	assert_contains "path $lib/" "$(cat "$work/python.log")" "without a virtualenv the python3 on PATH runs ${cmd%% *}"
	assert_equal "" "$(cat "$work/err")" "and ${cmd%% *} says nothing of it"
done

# No python3 at all, as on a FreeBSD that installed python3.12 alone: the
# first of python3.14 down to python3.9 on PATH runs it. The PATH holds the
# one tool the launchers call besides their shell's builtins, and that one.
mkdir -p "$work/bare"
ln -s "$(command -v dirname)" "$work/bare/dirname"
fake "$work/bare" py311
mv "$work/bare/python3" "$work/bare/python3.11"
for cmd in "xymonapi-mcp" "xymonapi-rag search x" "xymonapi-connect http://127.0.0.1:1"; do
	: > "$work/python.log"; : > "$work/err"
	# shellcheck disable=SC2086 # the command's words are meant to split
	XYMONAPI_PYTHON="" PATH="$work/bare" "$prefix/bin/"$cmd < /dev/null > /dev/null 2> "$work/err" || true
	assert_contains "py311 $lib/" "$(cat "$work/python.log")" "with no python3, python3.11 on PATH runs ${cmd%% *} ($(cat "$work/err"))"
done

# A command whose modules are missing says what installs them.
rc=0
XYMONAPI_PYTHON="$work/lacks/python3" "$ROOT/plugins/xymonapi/xymonapi.sh" < /dev/null > /dev/null 2> "$work/err" || rc=$?
assert_equal "77" "$rc" "the API without its modules cannot run here"
assert_contains "XYMONHOME=... ./install.sh venv-server installs them" "$(cat "$work/err")" "and says what installs them"

# An install that needs modules, with a Python that has them: the virtualenv
# is made from it, with --system-site-packages, and nothing is fetched.
: > "$work/python.log"
"$ROOT/install.sh" install-tools xymonapi-rag PREFIX="$prefix" PYTHON="$work/has/python3" >"$work/install2.log" 2>&1 \
	|| fail "install.sh install-tools failed: $(tail -n 5 "$work/install2.log")"
assert_contains "has -m venv --system-site-packages $lib/venv" "$(cat "$work/python.log")" "a Python with the modules makes the virtualenv, sharing its modules"
assert_not_contains "pip" "$(cat "$work/python.log")" "and nothing is installed"
assert_contains "Made $lib/venv from $work/has/python3" "$(cat "$work/install2.log")" "and the install says so"

# A virtualenv there that lacks a module: said, for ./install.sh venv-server, and nothing
# fetched; one that has them: nothing said.
mkdir -p "$lib/venv/bin"; cp "$work/lacks/python3" "$lib/venv/bin/python3"
"$ROOT/install.sh" install-tools xymonapi-rag PREFIX="$prefix" >"$work/install3.log" 2>&1 \
	|| fail "install.sh install-tools failed: $(tail -n 5 "$work/install3.log")"
assert_contains "The virtualenv $lib/venv lacks fastembed numpy" "$(cat "$work/install3.log")" "a virtualenv lacking the modules is said"
fake "$lib/venv/bin" venv
"$ROOT/install.sh" install-tools xymonapi-rag PREFIX="$prefix" >"$work/install4.log" 2>&1 \
	|| fail "install.sh install-tools failed: $(tail -n 5 "$work/install4.log")"
assert_not_contains "virtualenv" "$(cat "$work/install4.log")" "and one that has them, nothing"

# ./install.sh venv-tools makes the virtualenv with PYTHON, where only plugins
# without modules are installed, so that nothing is fetched; run again, it
# keeps the one there; and the launcher takes it without a word.
prefix2=$work/prefix2
"$ROOT/install.sh" install-tools xymonapi-mcp PREFIX="$prefix2" >"$work/install5.log" 2>&1 \
	|| fail "install.sh install-tools failed: $(tail -n 5 "$work/install5.log")"
"$ROOT/install.sh" venv-tools xymonapi-mcp PREFIX="$prefix2" PYTHON="$real" >"$work/venv.log" 2>&1 \
	|| fail "install.sh venv-tools failed: $(tail -n 5 "$work/venv.log")"
[ -x "$prefix2/libexec/xymon-plugins/venv/bin/python3" ] || fail "install.sh venv-tools made no venv/bin/python3"
assert_contains "run with $prefix2/libexec/xymon-plugins/venv/bin/python3" "$(cat "$work/venv.log")" "./install.sh venv-tools says what the plugins now run with"
: > "$prefix2/libexec/xymon-plugins/venv/kept"
"$ROOT/install.sh" venv-tools PREFIX="$prefix2" PYTHON="$real" >"$work/venv2.log" 2>&1 \
	|| fail "install.sh venv-tools at the top failed: $(tail -n 5 "$work/venv2.log")"
assert_file_exists "$prefix2/libexec/xymon-plugins/venv/kept"
: > "$work/err"
XYMONAPI_PYTHON="" "$prefix2/bin/xymonapi-mcp" < /dev/null > /dev/null 2> "$work/err" || true
assert_equal "" "$(cat "$work/err")" "and the launcher takes it without a word"

# On a terminal the hints are offers. A Python lacking the modules, which
# makes a virtualenv whose python3 records what it is asked: "y" makes it
# and installs into it every installed plugin's modules; "N" leaves the hint.
fake "$work/venvpy" venvpy
mkdir -p "$work/maker"
cat > "$work/maker/python3" <<STUB
#!/bin/sh
case "\$*" in
"-m venv "*) mkdir -p "\$3/bin"; cp "$work/venvpy/python3" "\$3/bin/python3"; exit 0 ;;
*"print("*) echo "fastembed numpy" ;;
*find_spec*) exit 1 ;;
esac
exit 0
STUB
chmod 755 "$work/maker/python3"
py=${XYMONAPI_PYTHON:-python3}
for yn in y N; do
	pre=$work/offer-$yn
	: > "$work/python.log"
	rc=0
	"$py" "$ROOT/tests/lib/answer.py" '[y/N] ' "$yn" \
		"$ROOT/install.sh" install-tools xymonapi-rag PREFIX="$pre" PYTHON="$work/maker/python3" > "$work/offer-$yn.log" 2>&1 || rc=$?
	[ "$rc" -eq 0 ] || fail "install.sh install-tools answering $yn failed with $rc: $(tail -n 5 "$work/offer-$yn.log")"
	assert_contains "xymonapi-rag needs fastembed numpy, which no Python here has (only to keep an index on this machine: search and ask through the server need none). Make a virtualenv at $pre/libexec/xymon-plugins/venv with $work/maker/python3, and install them from PyPI? [y/N]" \
		"$(cat "$work/offer-$yn.log")" "on a terminal, the install offers the virtualenv, saying what the modules are for here"
	if [ "$yn" = y ]; then
		assert_contains "venvpy -m pip install -q -r $pre/libexec/xymon-plugins/xymonapi-rag/requirements.txt" "$(cat "$work/python.log")" "y makes it and installs the modules into it"
	else
		[ -e "$pre/libexec/xymon-plugins/venv" ] && fail "N made a virtualenv"
		assert_contains "./install.sh venv-tools PYTHON=$work/maker/python3 makes one" "$(cat "$work/offer-$yn.log")" "N leaves the hint"
	fi
done
# A virtualenv there that lacks them: "y" installs them into it.
pre=$work/offer-lacks
mkdir -p "$pre/libexec/xymon-plugins/venv/bin"
printf '#!/bin/sh\nprintf "lacksvenv %%s\\n" "$*" >> "%s/python.log"\ncase "$*" in *"print("*) echo "fastembed numpy" ;; *find_spec*) exit 1 ;; esac\nexit 0\n' "$work" > "$pre/libexec/xymon-plugins/venv/bin/python3"
chmod 755 "$pre/libexec/xymon-plugins/venv/bin/python3"
: > "$work/python.log"
rc=0
"$py" "$ROOT/tests/lib/answer.py" '[y/N] ' y \
	"$ROOT/install.sh" install-tools xymonapi-rag PREFIX="$pre" > "$work/offer-lacks.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "install.sh install-tools over a lacking virtualenv failed with $rc: $(tail -n 5 "$work/offer-lacks.log")"
assert_contains "lacks fastembed numpy, which xymonapi-rag needs (only to keep an index" "$(cat "$work/offer-lacks.log")" "a virtualenv lacking the modules is offered them"
assert_contains "lacksvenv -m pip install -q -r $pre/libexec/xymon-plugins/xymonapi-rag/requirements.txt" "$(cat "$work/python.log")" "and y installs them into it"

pass "a launcher runs with XYMONAPI_PYTHON, else the virtualenv beside the plugins, else the python3 on PATH, asking nothing; an install makes the virtualenv from a Python that has the modules, fetching nothing, and otherwise says which ./install.sh venv-server would use, or on a terminal offers to make or complete it; a command lacking modules says what installs them"
