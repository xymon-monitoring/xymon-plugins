#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Start the Xymon API: xymonapi(8).
#
# Xymon itself needs no Python, so this is the one place that finds out
# whether the API can run here. Exit 77 says it cannot -- no Python 3.9, or a
# module missing -- as distinct from 1, a configuration error; the tests skip
# on 77, as they skip on a missing compiler.

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
	echo "xymonapi: $PYTHON not found${tried:+, $tried}; the API needs Python 3.9 or later" >&2
	exit 77
}
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || {
	echo "xymonapi: `$PYTHON -V 2>&1` is too old; the API needs Python 3.9 or later" >&2
	exit 77
}
# The module checks run from this script's directory: from the caller's, a
# directory there named like a module would pass for it.
missing=`cd "$here" && "$PYTHON" -c 'import importlib.util as u
print(" ".join(m for m in ("fastapi", "uvicorn", "yaml") if u.find_spec(m) is None))'`
if [ -n "$missing" ]; then
	echo "xymonapi: missing Python modules: $missing: XYMONHOME=... ./install.sh venv installs them in the virtualenv beside the plugins, or name a Python that has them in XYMONAPI_PYTHON" >&2
	exit 77
fi

if [ -z "$XYMSRV" ]; then
	echo "xymonapi: XYMSRV is not set; start it from xymonlaunch with ENVFILE, or through xymoncmd" >&2
	exit 1
fi

# HOST:PORT, or [ADDRESS]:PORT for IPv6. The default stays on this machine.
listen=${XYMONAPI_LISTEN:-127.0.0.1:1986}
port=${listen##*:}
host=`echo "${listen%:*}" | sed -e 's/^\[//' -e 's/\]$//'`

# The Unix socket for this machine's own clients, which need no password
# there: XYMONAPI_SOCKET, or $XYMONVAR/xymonapi/api.sock; set empty, none.
sock=${XYMONAPI_SOCKET-${XYMONVAR:+$XYMONVAR/xymonapi/api.sock}}

# TLS, with xymond's own certificate and key (xymon-tls(7)) unless others
# are named: when both files are there the API speaks HTTPS, when neither is
# it speaks HTTP, and one without the other is a mistake to report. A key
# that others can read is refused, as xymond refuses it.
cert=${XYMONAPI_TLS_CERT:-${XYMONHOME:-/nonexistent}/etc/tls/xymond.pem}
key=${XYMONAPI_TLS_KEY:-${XYMONHOME:-/nonexistent}/etc/tls/xymond.key}
tls=""
if [ -n "$XYMONAPI_TLS_CERT$XYMONAPI_TLS_KEY" ] || [ -e "$cert" ] || [ -e "$key" ]; then
	[ -r "$cert" ] || { echo "xymonapi: cannot read the TLS certificate $cert (XYMONAPI_TLS_CERT)" >&2; exit 1; }
	[ -r "$key" ] || { echo "xymonapi: cannot read the TLS key $key (XYMONAPI_TLS_KEY)" >&2; exit 1; }
	case `ls -ld "$key" | cut -c5-10` in
		------) ;;
		*) echo "xymonapi: the TLS key $key is readable by others; make it mode 600" >&2; exit 1 ;;
	esac
	tls="--ssl-certfile $cert --ssl-keyfile $key"
	export XYMONAPI_TLS=1
fi

cd "$here" || exit 1
# By its full path, as the task names it: a restart finds the API by its
# directory in the command line, pkill -f "$XYMONHOME/ext/xymonapi/", which
# a bare app.py would not show.
# shellcheck disable=SC2086 # tls is two options and their files, or nothing
exec "$PYTHON" "`pwd`/app.py" --host "$host" --port "$port" ${sock:+--socket "$sock"} $tls
