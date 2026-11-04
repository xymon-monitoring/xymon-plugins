#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Run the search over Xymon's manual pages and history, xymonapi-rag(1):
# xymonapi-rag.sh index | search QUESTION | ask QUESTION.
#
# As xymonapi.sh does, exit 77 when it cannot run here -- no Python 3.9, or
# a module of requirements.txt missing -- and say why. The modules are
# checked by xymonrag.py itself, when a command needs them: a search through
# the API's index, or ask with it, needs none.

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
	echo "xymonapi-rag: $PYTHON not found${tried:+, $tried}; it needs Python 3.9 or later" >&2
	exit 77
}
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || {
	echo "xymonapi-rag: `$PYTHON -V 2>&1` is too old; it needs Python 3.9 or later" >&2
	exit 77
}
exec "$PYTHON" "$here/xymonrag.py" "$@"
