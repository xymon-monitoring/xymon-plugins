#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-web-snippet.sh
#
# A plugin's web server snippets, the conf: line of its PLUGIN, are
# installed in ext/PLUGIN, where removing the plugin, or ext/PLUGIN by hand,
# takes them away; the web server includes them in a way that skips a file
# that is gone. An admin's edit survives an install. A snippet an older
# install wrote in $XYMONHOME/etc is left there, since a web server may still
# include it, and its content, the admin's edits with it, is what ext/PLUGIN
# gets the first time, which the install says.
#
# Installed into a scratch directory. That Apache's IncludeOptional and the
# wildcard include of nginx and lighttpd skip a missing file is the web
# servers' own behaviour, not run here.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
snippets=$(sed -n 's/^conf: *//p' "$ROOT/plugins/xymonapi/PLUGIN")
[ -n "$snippets" ] || fail "plugins/xymonapi/PLUGIN names no snippet"

install() { "$ROOT/install.sh" install-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/$1.log" 2>&1 \
	|| fail "install-server ($1) failed: $(tail -n 5 "$work/$1.log")"; }

install first
for c in $snippets; do
	cmp -s "$ROOT/plugins/xymonapi/$c" "$home/ext/xymonapi/$c" || fail "[S16] $c is not in ext/xymonapi as shipped"
	[ -e "$home/etc/$c" ] && fail "[S16] the install wrote $c in etc/"
done
assert_contains "IncludeOptional" "$(cat "$work/first.log")" "[S16] the install says to include it with IncludeOptional"

echo "# the admin's port" >> "$home/ext/xymonapi/xymonapi-nginx.conf"
cp "$home/ext/xymonapi/xymonapi-nginx.conf" "$work/edited"
install again
cmp -s "$work/edited" "$home/ext/xymonapi/xymonapi-nginx.conf" || fail "[S16] an install undid the admin's edit to the nginx snippet"
[ -e "$home/ext/.xymonapi.xymonapi-nginx.conf" ] && fail "[S16] the snippet set aside was left in ext/"

"$ROOT/install.sh" uninstall-server xymonapi XYMONHOME="$home" MANDIR="$work/man" >/dev/null 2>&1 || fail "uninstall-server failed"
for c in $snippets; do
	[ -e "$home/ext/xymonapi/$c" ] && fail "[S16] uninstall-server left $c"
done

# An older install's snippet in etc/, edited: left there, and copied, edits
# and all, into ext/xymonapi.
mkdir -p "$home/etc"
{ cat "$ROOT/plugins/xymonapi/xymonapi-apache.conf"; echo "# edited in etc"; } > "$home/etc/xymonapi-apache.conf"
cp "$home/etc/xymonapi-apache.conf" "$work/old"
install migrate
cmp -s "$work/old" "$home/etc/xymonapi-apache.conf" || fail "[S16] the older install's snippet in etc/ was changed"
cmp -s "$work/old" "$home/ext/xymonapi/xymonapi-apache.conf" || fail "[S16] ext/xymonapi did not get the older snippet, edits and all"
assert_contains "$home/etc/xymonapi-apache.conf, an older install's, is copied to" "$(cat "$work/migrate.log")" "[S16] the install says it copied the older snippet"
cmp -s "$ROOT/plugins/xymonapi/xymonapi-nginx.conf" "$home/ext/xymonapi/xymonapi-nginx.conf" || fail "[S16] a snippet with no older copy is not the shipped one"
install migrate-again
assert_not_contains "an older install's" "$(cat "$work/migrate-again.log")" "[S16] the next install says it no more"

pass "a plugin's web server snippets live in ext/PLUGIN, keep the admin's edits, go with the plugin, and an older copy in etc/ is left there and carried over once"
