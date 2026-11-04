#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-install.sh
#
# ./install.sh install with XYMONHOME set puts
# the API, with its client, in $XYMONHOME/ext/xymonapi/,
# the search beside it, its manual page in man8/, and its task in
# $XYMONHOME/etc/tasks.d/xymonapi -- disabled, with ENVFILE naming that
# server's xymonserver.cfg. An install over one where the admin enabled the
# task leaves that file alone: putting DISABLED back would stop the API at
# the next upgrade, with nothing to say why. Without XYMONHOME it installs
# nothing and says so. The Apache snippet goes to $XYMONHOME/etc, kept too
# once there. ./install.sh install puts the MCP server and the search commands
# under PREFIX, with two commands in bin that run them from there, and
# xymonapi's client alone beside them, not the API. Installing
# again replaces each plugin's directory, so a file no longer shipped is
# gone, and says to restart the API; the client's virtualenv beside the
# plugins is kept. A plugin installed alone brings the plugins it needs
# beside it: xymonapi-rag on the server, the API with its client. The
# removal refuses a plugin another installed one needs, removes each
# plugin's files, manual page and task, and keeps the web server snippets
# and the data, saying so; on a laptop it says what to undo by hand.
#
# Installed into a scratch directory. No Python is needed: the API is copied,
# not run. Uses the test helpers of the Xymon tree in XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server

# Under a umask that would leave a new file readable by its owner alone: the
# task file must still be 644, like the others, whoever xymonlaunch runs as.
( umask 077 && "$ROOT/install.sh" install XYMONHOME="$home" MANDIR="$work/man" ) >"$work/install.log" 2>&1 \
	|| fail "install.sh install failed: $(tail -n 5 "$work/install.log")"

for f in app.py xymon.py xymonapi_client.py tokens.py openapi.yaml requirements.txt xymonapi.sh; do
	assert_file_exists "$home/ext/xymonapi/$f"
done
for f in xymonapi-rag/xymonrag.py xymonapi-rag/xymonapi-rag.sh xymonapi-rag/requirements.txt; do
	assert_file_exists "$home/ext/$f"
done
[ -x "$home/ext/xymonapi/xymonapi.sh" ] || fail "the launcher is not executable"
# Each plugin records its version beside its files: its release tag when
# the checkout is at one, else the version in its PLUGIN file.
for p in xymonapi xymonapi-rag; do
	assert_file_exists "$home/ext/$p/VERSION"
	want=$(git -C "$ROOT" describe --exact-match --tags --match "$p/v*" 2>/dev/null || sed -n 's/^version: *//p' "$ROOT/plugins/$p/PLUGIN")
	assert_equal "$want" "$(cat "$home/ext/$p/VERSION")" "$p/VERSION holds its tag or its PLUGIN version"
done
assert_file_exists "$work/man/man8/xymonapi.8"

task=$home/etc/tasks.d/xymonapi
assert_file_exists "$task"
grep -q '^[[:space:]]*DISABLED$' "$task" || fail "the task is not shipped DISABLED: $(cat "$task")"
grep -q "^[[:space:]]*ENVFILE $home/etc/xymonserver.cfg\$" "$task" \
	|| fail "ENVFILE does not name this server's xymonserver.cfg: $(grep ENVFILE "$task")"
grep -q '@XYMONHOME@' "$task" && fail "@XYMONHOME@ was left unreplaced in $task"
mode=$(ls -l "$task" | cut -c1-10)
assert_equal "-rw-r--r--" "$mode" "the task file's mode under umask 077"

# An update replaces each plugin's directory: a file the new version no
# longer ships does not stay behind, and the install says to restart the API.
echo 'stale' > "$home/ext/xymonapi/gone.py"
echo 'stale' > "$home/ext/xymonapi-rag/gone.py"
"$ROOT/install.sh" install XYMONHOME="$home" MANDIR="$work/man" >"$work/update.log" 2>&1 \
	|| fail "installing over an install failed: $(tail -n 5 "$work/update.log")"
[ -e "$home/ext/xymonapi/gone.py" ] && fail "a file no longer shipped stayed in ext/xymonapi after an update"
[ -e "$home/ext/xymonapi-rag/gone.py" ] && fail "a file no longer shipped stayed in ext/xymonapi-rag after an update"
assert_file_exists "$home/ext/xymonapi/app.py"
# The install stops a running API itself (xymonapi-auth.sh): with none
# running here it stops nothing, and asks no step of the admin.
assert_not_contains "Stopped" "$(cat "$work/update.log")" "with no API running, the install stops nothing"
assert_not_contains "pkill" "$(cat "$work/update.log")" "and asks no pkill of the admin"

# The admin enables the API, and the next install must not undo it.
grep -v '^[[:space:]]*DISABLED$' "$task" > "$work/enabled"
cp "$work/enabled" "$task"
"$ROOT/install.sh" install XYMONHOME="$home" MANDIR="$work/man" >"$work/reinstall.log" 2>&1 \
	|| fail "installing a second time failed: $(tail -n 5 "$work/reinstall.log")"
cmp -s "$work/enabled" "$task" \
	|| fail "a second install changed the task file the admin had enabled: $(cat "$task")"

# A server directory with a space, an & and a | in its name: the paths are
# quoted, and the replacement sed makes in the task files is escaped.
odd="$work/x y&z|w"
"$ROOT/install.sh" install XYMONHOME="$odd" MANDIR="$work/man 2" >"$work/odd.log" 2>&1 \
	|| fail "install.sh install into a directory with a space, & and | failed: $(tail -n 5 "$work/odd.log")"
assert_file_exists "$odd/ext/xymonapi/xymonapi.sh"
assert_file_exists "$work/man 2/man8/xymonapi.8"
grep -qF "ENVFILE $odd/etc/xymonserver.cfg" "$odd/etc/tasks.d/xymonapi" \
	|| fail "the task file does not name that directory as it is: $(grep ENVFILE "$odd/etc/tasks.d/xymonapi")"
grep -qF "ENVFILE $odd/etc/xymonserver.cfg" "$odd/etc/tasks.d/xymonapi-rag" \
	|| fail "the index task file does not name that directory as it is: $(grep ENVFILE "$odd/etc/tasks.d/xymonapi-rag")"

assert_file_exists "$home/etc/xymonapi-apache.conf"
grep -q 'ProxyPass ' "$home/etc/xymonapi-apache.conf" || fail "the Apache snippet has no ProxyPass"
grep -q 'proxy_pass ' "$home/etc/xymonapi-nginx.conf" || fail "the nginx snippet has no proxy_pass"
grep -q 'proxy.server' "$home/etc/xymonapi-lighttpd.conf" || fail "the lighttpd snippet has no proxy.server"
assert_contains 'Installed. Enable the API' "$(cat "$work/install.log")" "the install says what to do next"
echo "# mine" > "$home/etc/xymonapi-apache.conf"
"$ROOT/install.sh" install XYMONHOME="$home" MANDIR="$work/man" >/dev/null 2>&1 || fail "a third install failed"
assert_equal "# mine" "$(cat "$home/etc/xymonapi-apache.conf")" "an edited Apache snippet is kept"

# One plugin alone brings what it needs beside it: on the server,
# xymonapi-rag needs the API that serves its index, and its client it reads
# the API with.
alone=$work/alone
"$ROOT/install.sh" install xymonapi-rag XYMONHOME="$alone" MANDIR="$work/man-alone" >"$work/alone.log" 2>&1 \
	|| fail "install.sh install of xymonapi-rag alone failed: $(tail -n 5 "$work/alone.log")"
for p in xymonapi xymonapi-rag; do
	assert_file_exists "$alone/ext/$p/VERSION"
done

# The tools side: no Xymon here, PREFIX with a space in its name.
prefix="$work/client prefix"
"$ROOT/install.sh" install PREFIX="$prefix" >"$work/client.log" 2>&1 \
	|| fail "install.sh install failed: $(tail -n 5 "$work/client.log")"
# An update replaces the plugin's directory there too, and leaves the
# virtualenv an earlier setup made beside the plugins alone.
mkdir -p "$prefix/libexec/xymon-plugins/venv" && : > "$prefix/libexec/xymon-plugins/venv/kept"
: > "$prefix/libexec/xymon-plugins/xymonapi-rag/gone.py"
"$ROOT/install.sh" install PREFIX="$prefix" >"$work/client2.log" 2>&1 \
	|| fail "install.sh install a second time failed: $(tail -n 5 "$work/client2.log")"
[ -e "$prefix/libexec/xymon-plugins/xymonapi-rag/gone.py" ] && fail "a file no longer shipped stayed in the client's xymonapi-rag"
assert_file_exists "$prefix/libexec/xymon-plugins/venv/kept"
for f in xymonapi-mcp/server.py xymonapi-mcp/xymonapi-mcp.sh xymonapi/xymonapi_client.py xymonapi/xymonapi-connect.sh \
         xymonapi-rag/xymonrag.py xymonapi-rag/xymonapi-rag.sh xymonapi-rag/requirements.txt xymonapi-mcp/VERSION xymonapi-rag/VERSION; do
	assert_file_exists "$prefix/libexec/xymon-plugins/$f"
done
assert_file_exists "$prefix/share/man/man1/xymonapi-mcp.1"
assert_file_exists "$prefix/share/man/man1/xymonapi-rag.1"
assert_file_exists "$prefix/share/man/man1/xymonapi-connect.1"
[ -x "$prefix/bin/xymonapi-connect" ] || fail "bin/xymonapi-connect is not executable"
[ -x "$prefix/bin/xymonapi-mcp" ] || fail "bin/xymonapi-mcp is not executable"
[ -x "$prefix/bin/xymonapi-rag" ] || fail "bin/xymonapi-rag is not executable"
grep -qF "\"$prefix/libexec/xymon-plugins/xymonapi-rag/xymonapi-rag.sh\"" "$prefix/bin/xymonapi-rag" \
	|| fail "bin/xymonapi-rag does not run the installed launcher, quoted: $(cat "$prefix/bin/xymonapi-rag")"
[ -e "$prefix/libexec/xymon-plugins/xymonapi/app.py" ] && fail "install installed the API"
# The installed xymonapi-rag runs: --help needs Python alone, and finds
# xymonapi_client.py in xymonapi/ beside it, as in the repository.
if command -v "${XYMONAPI_PYTHON:-python3}" >/dev/null 2>&1; then
	XYMONAPI_PYTHON="${XYMONAPI_PYTHON:-python3}" "$prefix/bin/xymonapi-rag" --help > "$work/help.out" 2>&1 \
		|| fail "the installed xymonapi-rag --help failed: $(cat "$work/help.out")"
	assert_contains 'search' "$(cat "$work/help.out")" "and names its commands"
fi

# Removing: a plugin another installed one needs is refused, naming it;
# the whole side removes each plugin's files, manual page and task, keeps
# the web server snippets and the data, and says so. On a laptop it also
# says what register did besides.
for p in xymonapi; do
	rc=0
	"$ROOT/install.sh" remove "$p" XYMONHOME="$home" MANDIR="$work/man" >"$work/un-$p.log" 2>&1 || rc=$?
	[ "$rc" -ne 0 ] || fail "removing $p while xymonapi-mcp and xymonapi-rag need it succeeded"
	# Any of those installed that need it; the first, by name, is xymonapi-mcp.
	assert_contains "$p is needed by xymonapi-mcp" "$(cat "$work/un-$p.log")" "and says which plugin needs $p"
	assert_file_exists "$home/ext/$p/VERSION"
done
"$ROOT/install.sh" remove XYMONHOME="$home" MANDIR="$work/man" >"$work/remove.log" 2>&1 \
	|| fail "install.sh remove failed: $(tail -n 5 "$work/remove.log")"
for f in ext/xymonapi ext/xymonapi-mcp ext/xymonapi-rag etc/tasks.d/xymonapi etc/tasks.d/xymonapi-rag; do
	[ -e "$home/$f" ] && fail "install.sh remove left $f"
done
[ -e "$work/man/man8/xymonapi.8" ] && fail "install.sh remove left the manual page xymonapi.8"
[ -e "$work/man/man1/xymonapi-rag.1" ] && fail "install.sh remove left the manual page xymonapi-rag.1"
assert_file_exists "$home/etc/xymonapi-apache.conf"
assert_contains "take its Include out of the web server first" "$(cat "$work/remove.log")" "remove says the snippets are kept, and how to remove them"
assert_contains "XYMONAPI_TOKENS" "$(cat "$work/remove.log")" "and that the tokens file is kept"

rc=0
"$ROOT/install.sh" remove xymonapi PREFIX="$prefix" >"$work/unc-api.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "remove of xymonapi's client while xymonapi-mcp needs it succeeded"
assert_contains "needed by xymonapi-mcp" "$(cat "$work/unc-api.log")" "and says which plugin needs it"
"$ROOT/install.sh" remove PREFIX="$prefix" >"$work/unclient.log" 2>&1 \
	|| fail "install.sh remove failed: $(tail -n 5 "$work/unclient.log")"
[ -e "$prefix/libexec/xymon-plugins" ] && fail "install.sh remove left $prefix/libexec/xymon-plugins: $(ls -A "$prefix/libexec/xymon-plugins")"
for f in bin/xymonapi-mcp bin/xymonapi-rag share/man/man1/xymonapi-mcp.1 share/man/man1/xymonapi-rag.1; do
	[ -e "$prefix/$f" ] && fail "install.sh remove left $f"
done
assert_contains "claude mcp remove" "$(cat "$work/unclient.log")" "remove says what register did besides"

pass "./install.sh install puts the server plugins in ext/ with disabled tasks and the Apache snippet, keeps what the admin edited, takes odd directory names, replaces each plugin's directory on update; install lays out the client side; uninstall removes them, refusing one another needs"
