#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-dist-declared.sh
#
# What install-server stages for /plugins, ext/xymon-plugins-dist, is for
# each plugin only what its PLUGIN file names -- itself, README.md, each
# side's files and manual page, the task and the snippets -- with
# install.sh and LICENSE: a file left beside them in the checkout, as a
# key or a note would be, is not staged, and so not served. What an older
# install staged is pruned to the same; a name with a / or a link stops
# the install.
#
# Run from a copy of the checkout, in a scratch directory, so that the file
# added beside a plugin's never touches the real one.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
repo=$work/repo
mkdir -p "$repo"
cp -R "$ROOT/install.sh" "$ROOT/LICENSE" "$ROOT/plugins" "$repo/"
echo "not for anyone" > "$repo/plugins/xymonapi/secret.key"
mkdir -p "$repo/plugins/xymonapi/notes"
echo "nor this" > "$repo/plugins/xymonapi/notes/todo"

server_tree "$work/server"
dist=$work/server/ext/xymon-plugins-dist
# What an older install left: xymonapi-rag, installed, staged whole with a
# secret; old-name, staged with its PLUGIN file but installed no more;
# nameless, staged with no PLUGIN file; a stray file at the top.
mkdir -p "$work/server/ext/xymonapi-rag" "$dist/plugins/xymonapi-rag" "$dist/plugins/old-name" "$dist/plugins/nameless"
echo 0.0.1 > "$work/server/ext/xymonapi-rag/VERSION"
cp "$ROOT/plugins/xymonapi-rag/PLUGIN" "$dist/plugins/xymonapi-rag/"
cp "$ROOT/plugins/xymonapi-rag/PLUGIN" "$dist/plugins/old-name/"
echo "left" > "$dist/plugins/xymonapi-rag/secret.key"
echo "left" > "$dist/plugins/old-name/secret.key"
echo "left" > "$dist/plugins/nameless/secret.key"
echo "left" > "$dist/stray"
"$repo/install.sh" install-server xymonapi XYMONHOME="$work/server" MANDIR="$work/man" </dev/null >"$work/install.log" 2>&1 \
	|| fail "install-server failed: $(tail -n 5 "$work/install.log")"
[ -e "$dist/plugins/xymonapi-rag/secret.key" ] && fail "[S19] a file an older install staged beside an installed plugin's is still served"
assert_file_exists "$dist/plugins/xymonapi-rag/PLUGIN"
[ -e "$dist/plugins/old-name" ] && fail "[S19] the stage of a plugin installed no more is still served"
[ -e "$dist/plugins/nameless" ] && fail "[S19] a staged directory with no PLUGIN file is still served"
[ -e "$dist/stray" ] && fail "[S19] a file at the top of the stage is still served"

"$repo/install.sh" install-server XYMONHOME="$work/server" MANDIR="$work/man" </dev/null >"$work/install.log" 2>&1 \
	|| fail "install-server failed: $(tail -n 5 "$work/install.log")"

[ -e "$dist/plugins/xymonapi/secret.key" ] && fail "[S19] a file beside the plugin's in the checkout was staged"
[ -e "$dist/plugins/xymonapi/notes" ] && fail "[S19] a directory beside the plugin's in the checkout was staged"
assert_file_exists "$dist/install.sh"
assert_file_exists "$dist/LICENSE"

# Each plugin staged holds exactly what its PLUGIN file names, and every
# plugin installed is staged.
field() { sed -n "s/^$2: //p" "$repo/plugins/$1/PLUGIN"; }
for d in "$dist"/plugins/* "$dist"/plugins/.[!.]*; do
	[ -e "$d" ] || continue
	p=${d##*/}
	want=$( { echo PLUGIN; [ ! -e "$repo/plugins/$p/README.md" ] || echo README.md
		for k in server-files tools-files server-manual tools-manual task conf; do
			for f in $(field "$p" "$k"); do echo "$f"; done
		done; } | sort -u)
	have=$(ls -A "$d" | sort)
	assert_equal "$want" "$have" "[S19] $p staged exactly what its PLUGIN file names"
done
[ -x "$dist/plugins/xymonapi/xymonapi.sh" ] || fail "[S19] an executable file lost its mode when staged"
for d in "$work"/server/ext/*; do
	[ -f "$d/VERSION" ] || continue
	assert_file_exists "$dist/plugins/${d##*/}/PLUGIN"
done

# Links in the stage are removed, not written through: plugins/ a link to
# a directory outside, install.sh a link to a file outside.
mkdir -p "$work/elsewhere"
echo "keep" > "$work/elsewhere/keep"
echo "keep" > "$work/elsewhere.file"
rm -rf "$dist/plugins" "$dist/install.sh"
ln -s "$work/elsewhere" "$dist/plugins"
ln -s "$work/elsewhere.file" "$dist/install.sh"
"$repo/install.sh" install-server XYMONHOME="$work/server" MANDIR="$work/man" </dev/null >"$work/install.log" 2>&1 \
	|| fail "install-server over linked stage entries failed: $(tail -n 5 "$work/install.log")"
assert_equal "keep" "$(cat "$work/elsewhere/keep")" "[S19] a directory a staged link pointed to is untouched"
[ -e "$work/elsewhere/xymonapi" ] && fail "[S19] a plugin was staged through a link"
assert_equal "keep" "$(cat "$work/elsewhere.file")" "[S19] a file a staged link pointed to is not overwritten"
[ -L "$dist/plugins" ] || [ -L "$dist/install.sh" ] && fail "[S19] a link is left in the stage"

# A PLUGIN file naming a file outside its directory, a needs: naming one
# outside plugins/, or a plugin file that is a link, stops the install
# before anything outside is copied, on either side.
echo "S19-outside-secret" > "$work/outside.key"
cp -R "$repo" "$work/repo2"
sed -e 's|^server-files: |server-files: ../../../outside.key |' "$repo/plugins/xymonapi-mcp/PLUGIN" > "$work/repo2/plugins/xymonapi-mcp/PLUGIN"
server_tree "$work/server2"
rc=0
"$work/repo2/install.sh" install-server xymonapi-mcp XYMONHOME="$work/server2" MANDIR="$work/man" </dev/null >"$work/esc.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "[S19] an install whose PLUGIN file names ../ succeeded"
assert_contains "no file of its own directory" "$(cat "$work/esc.log")" "[S19] and says why"
[ -z "$(find "$work/server2" -name outside.key)" ] || fail "[S19] a file outside the plugin was copied"

cp -R "$repo" "$work/repo4"
sed -e 's|^needs: .*|needs: ../victim|' "$repo/plugins/xymonapi-mcp/PLUGIN" > "$work/repo4/plugins/xymonapi-mcp/PLUGIN"
server_tree "$work/server4"
rc=0
"$work/repo4/install.sh" install-server xymonapi-mcp XYMONHOME="$work/server4" MANDIR="$work/man" </dev/null >"$work/needs.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "[S19] an install whose needs: names ../ succeeded"
assert_contains "not a plugin name" "$(cat "$work/needs.log")" "[S19] and says why"

cp -R "$repo" "$work/repo3"
rm "$work/repo3/plugins/xymonapi-mcp/server.py"
ln -s "$work/outside.key" "$work/repo3/plugins/xymonapi-mcp/server.py"
server_tree "$work/server3"
for side in server tools; do
	rc=0
	"$work/repo3/install.sh" "install-$side" xymonapi-mcp XYMONHOME="$work/server3" PREFIX="$work/prefix3" MANDIR="$work/man" \
		</dev/null >"$work/link.log" 2>&1 || rc=$?
	[ "$rc" -ne 0 ] || fail "[S19] install-$side of a plugin file that is a link succeeded"
	assert_contains "is a link" "$(cat "$work/link.log")" "[S19] install-$side says why"
done
[ -z "$(grep -rl S19-outside-secret "$work/server3" "$work/prefix3" 2>/dev/null)" ] || fail "[S19] what a link pointed to was copied"

pass "install-server stages for /plugins only what each PLUGIN file names, with install.sh and LICENSE: a file left beside them is not served, an older stage is pruned to the same, links in it removed and not followed, and a name leaving the directory or a link stops the install"
