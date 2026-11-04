#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Connect this machine to the Xymon API: xymonapi-connect(1). It runs
# xymonapi_client.py beside it, which needs Python 3.9 or later and nothing
# else.

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
	echo "xymonapi-connect: $PYTHON not found${tried:+, $tried}; it needs Python 3.9 or later" >&2
	exit 77
}
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || {
	echo "xymonapi-connect: `$PYTHON -V 2>&1` is too old; it needs Python 3.9 or later" >&2
	exit 77
}
exec "$PYTHON" "$here/xymonapi_client.py" connect "$@"
