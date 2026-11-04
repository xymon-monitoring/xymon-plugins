#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Start the MCP server for the Xymon API, xymonapi-mcp(1), on stdio. This is
# the command an AI client is configured to run.
#
# xymonapi-mcp register URL [NAME] instead registers it with Claude Code and
# Codex, after xymonapi-connect(1), beside it, has connected this machine to
# the API at URL.
# It needs Python 3.9 or later and nothing else: the standard library speaks
# the protocol.
#
# As xymonapi.sh does, exit 77 when it cannot run here -- no Python 3.9 --
# and say why on stderr, which the client logs: stdout carries the protocol
# and nothing else.

# The Python to run with: XYMONAPI_PYTHON when set; else the virtualenv
# beside the plugins, ../venv, which ./install.sh venv makes
# with their modules; else
# python3 on PATH, without a word: a command that needs a module it lacks
# says which, and what installs it, when it needs it.
here=`dirname "$0"`
venv=`cd "$here/.." && pwd`/venv
tried=""
if [ -n "${XYMONAPI_PYTHON:-}" ]; then
	PYTHON=$XYMONAPI_PYTHON
elif [ -x "$venv/bin/python3" ]; then
	PYTHON=$venv/bin/python3
else
	# By any of its usual names: FreeBSD, for one, installs python3.12 and
	# gives a plain python3 only with a package of its own.
	PYTHON=python3 tried="nor python3.14 down to python3.9"
	for p in python3 python3.14 python3.13 python3.12 python3.11 python3.10 python3.9; do
		if command -v "$p" >/dev/null 2>&1; then PYTHON=$p; break; fi
	done
fi

command -v "$PYTHON" >/dev/null 2>&1 || {
	echo "xymonapi-mcp: $PYTHON not found${tried:+, $tried}; it needs Python 3.9 or later" >&2
	exit 77
}
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || {
	echo "xymonapi-mcp: `$PYTHON -V 2>&1` is too old; it needs Python 3.9 or later" >&2
	exit 77
}

[ "${1:-}" = register ] || exec "$PYTHON" "$here/server.py"

# register URL [NAME]
case ${2:-} in -h|--help) echo "usage: xymonapi-mcp register URL [NAME]"; exit 0 ;; esac
[ $# -ge 2 ] && [ $# -le 3 ] || {
	echo "usage: xymonapi-mcp register URL [NAME]" >&2
	exit 2
}
url=$2
name=${3:-xymon}
# The connection first: a token kept while it works, else a password asked
# once. Its settings, shell-quoted, on stdout; its questions on stderr. It
# runs with the Python chosen above, so that the choice is made, and asked
# about, once; what the registration below carries is XYMONAPI_PYTHON as
# given, not that choice.
connect=$here/../xymonapi/xymonapi-connect.sh
settings=`XYMONAPI_PYTHON=$PYTHON "$connect" "$url" "$name"` || exit $?
XYMONAPI_TOKEN_FILE=""
XYMONAPI_CA=""
eval "$settings"
cmd=`cd "$here" && pwd`/xymonapi-mcp.sh

# The settings an AI client gives the server, as -e or --env options.
opts() {
	printf '%s\n' "$1" "XYMONAPI_URL=$XYMONAPI_URL"
	[ -n "$XYMONAPI_TOKEN_FILE" ] && printf '%s\n' "$1" "XYMONAPI_TOKEN_FILE=$XYMONAPI_TOKEN_FILE"
	[ -n "$XYMONAPI_CA" ] && printf '%s\n' "$1" "XYMONAPI_CA=$XYMONAPI_CA"
	[ -n "${XYMONAPI_PYTHON:-}" ] && printf '%s\n' "$1" "XYMONAPI_PYTHON=$XYMONAPI_PYTHON"
	return 0
}
# One option per line, read back into the arguments: a path with a space
# stays one word.
register() {
	client=$1 flag=$2; shift 2
	while IFS= read -r o; do set -- "$@" "$o"; done <<EOF
`opts "$flag"`
EOF
	if command -v "$client" >/dev/null 2>&1; then
		# A client that fails is said, by name, and the others still get
		# their registration: one half done and silence told a user neither
		# which tool failed nor that the other had succeeded.
		if "$@" -- "$cmd"; then
			echo "registered $name with $client"
		else
			echo "could not register $name with $client, which exited $?:" >&2
			printf ' %s' "$@" -- "$cmd" >&2; echo >&2
			failed=1
		fi
	else
		echo "$client is not here; to register $name with it later:"
		printf ' %s' "$@" -- "$cmd"; echo
	fi
}
claude mcp remove --scope user "$name" >/dev/null 2>&1 || true
register claude -e claude mcp add --scope user "$name"
codex mcp remove "$name" >/dev/null 2>&1 || true
register codex --env codex mcp add "$name"
exit ${failed:-0}
