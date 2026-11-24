#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-client-status.sh
#
# status and verify read a standalone client's tree as a server's (S15,
# S30, S35), changing nothing and remembering nothing: xymon-plugin's
# client part installed in a scratch client tree, status --client says it
# and its version; verify --client says ok and exits 0, a file changed or
# a link pointing elsewhere broken (3), a file no install wrote untidy
# (4); an install cut short is said by both. With no part named, a
# XYMONHOME naming the client tree is read as the client's, the tools
# beside it; without one, the client trees detection finds follow the
# servers', and one in doubt is said, not read (S24, S25). An ext/ not the
# person's is read all the same; a tree of another kind, a server's own
# client and one in doubt are refused (S35).

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
# Resolved: the installer names trees by their resolved path.
work=$(cd "$work" && pwd -P)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES= PREFIX="$work/tools"
mkdir -p "$HOME"
man=$work/man
mkdir -p "$man"
version=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymon-plugin/PLUGIN")

client_tree() {
	mkdir -p "$1/bin" "$1/etc" "$1/ext"
	: > "$1/bin/xymonclient.sh"; : > "$1/etc/xymonclient.cfg"
}
# state FILE -- every path under the scratch area with its mode, each
# file's cksum and each link's target, but the snapshots.
state() {
	find "$work" -mindepth 1 -path "$work/snap*" -prune -o -print | sort | while IFS= read -r p; do
		if [ -L "$p" ]; then printf '%s -> %s\n' "$p" "$(readlink "$p")"
		elif [ -f "$p" ]; then printf '%s %s %s\n' "$p" "$(ls -ldn "$p" | awk '{ print $1 }')" "$(cksum < "$p")"
		else printf '%s %s\n' "$p" "$(ls -ldn "$p" | awk '{ print $1 }')"; fi
	done > "$work/$1"
}
# x ARG... -- xymon-plugin ARG..., off a terminal; output in out, status in
# rc; the scratch area as it was after it, as both verbs change nothing.
x() {
	state snap-0
	rc=0; out=$("$ROOT/xymon-plugin" "$@" MANDIR="$man" </dev/null 2>&1) || rc=$?
	state snap-1
	cmp -s "$work/snap-0" "$work/snap-1" || fail "[S15] [S30] $*: changed something: $(diff "$work/snap-0" "$work/snap-1" || :)"
}

c=$work/plain/client
client_tree "$c"
d=$c/ext/xymon-plugin
"$ROOT/xymon-plugin" install --client xymon-plugin XYMONHOME="$c" MANDIR="$man" </dev/null >/dev/null 2>&1 || fail "install --client failed"
rm -rf "$work/cfg"

x status --client XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S15] status --client failed: $out"
assert_contains "Xymon client $c:" "$out" "[S15] status --client names the client's tree"
assert_contains "  xymon-plugin: $version installed, off; this copy has $version" "$out" "[S15] status --client says the plugin installed and its version"
assert_not_contains "Your tools" "$out" "[S15] --client keeps to the client"

x verify --client XYMONHOME="$c"
assert_equal 0 "$rc" "[S30] verify --client of an install as it was left exits 0: $out"
assert_contains "Xymon client: $c" "$out" "[S30] verify --client names the client's tree"
assert_contains "ok: xymon-plugin" "$out" "[S30] verify --client says ok"
assert_not_contains "Your tools" "$out" "[S30] --client keeps to the client"
[ ! -e "$work/cfg/xymon-plugin" ] || fail "[S25] verify --client remembered the installation"
# What the tools' plugins gone left is the tools', not the client's.
mkdir -p "$PREFIX/share/man/man1"; ln -s "$PREFIX/libexec/xymon-plugins/gone/gone.1" "$PREFIX/share/man/man1/gone.1"
x verify --client XYMONHOME="$c"
assert_equal 0 "$rc" "[S30] verify --client says nothing of the tools: $out"
rm -rf "$PREFIX"

# Broken: a file changed, the manual page's link pointing elsewhere.
cp "$d/xymon-plugin.8" "$work/page.kept"
echo changed >> "$d/xymon-plugin.8"
x verify --client XYMONHOME="$c"
assert_equal 3 "$rc" "[S30] a file changed in a client part exits 3: $out"
assert_contains "broken: xymon-plugin: xymon-plugin.8 changed: ./xymon-plugin update --client xymon-plugin" "$out" "[S30] a file changed is broken, naming update --client"
cp "$work/page.kept" "$d/xymon-plugin.8"
ln -sf /elsewhere "$man/man8/xymon-plugin.8"
x verify --client XYMONHOME="$c"
assert_equal 3 "$rc" "[S30] the page's link pointing elsewhere exits 3: $out"
assert_contains "broken: xymon-plugin: the link $man/man8/xymon-plugin.8 points to /elsewhere, not $d/xymon-plugin.8" "$out" "[S30] the page's link pointing elsewhere is broken"
ln -sf "$d/xymon-plugin.8" "$man/man8/xymon-plugin.8"

# Untidy: a file no install wrote, a .new and a .old, which cannot run;
# the task file's .new, this version's beside the administrator's; any
# other .new, no file of theirs; the .old, kept by an update (S7).
: > "$d/tasks.cfg.new"; : > "$d/xymon-plugin.new"; : > "$d/notes.old"
x verify --client XYMONHOME="$c"
assert_equal 4 "$rc" "[S30] a .new and a .old in a client part exit 4: $out"
assert_contains "untidy: xymon-plugin: tasks.cfg.new, this version's beside yours: compare, then remove it" "$out" "[S30] the task file's .new is untidy, beside the administrator's"
assert_contains "untidy: xymon-plugin: xymon-plugin.new is not what was installed: ./xymon-plugin update --client xymon-plugin" "$out" "[S30] any other .new is untidy"
assert_contains "untidy: xymon-plugin: notes.old, yours, kept by an update: compare, then remove it" "$out" "[S30] a .old is untidy, kept by an update"
rm -f "$d/tasks.cfg.new" "$d/xymon-plugin.new" "$d/notes.old"

# An ext/ not the person's: read all the same, as nothing changes.
realid=$(command -v id)
mkdir -p "$work/fakeid"
printf '#!/bin/sh\ncase "$*" in -u) echo 4242 ;; -un) echo someone-else ;; *) exec "%s" "$@" ;; esac\n' "$realid" > "$work/fakeid/id"
chmod 755 "$work/fakeid/id"
PATH="$work/fakeid:$PATH" x status --client XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] status --client of an ext/ not the person's was refused: $out"
assert_contains "xymon-plugin: $version installed" "$out" "[S35] status --client reads an ext/ not the person's"
PATH="$work/fakeid:$PATH" x verify --client XYMONHOME="$c"
assert_equal 0 "$rc" "[S35] verify --client reads an ext/ not the person's: $out"

# With no part named, XYMONHOME naming the client tree: the client's, and
# the tools.
x status XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S24] status, no part, on a client's tree failed: $out"
assert_contains "Xymon client $c:" "$out" "[S24] status, no part, reads the client's tree XYMONHOME names"
assert_contains "  xymon-plugin: $version installed" "$out" "[S24] and says what it holds"
assert_contains "Your tools, $PREFIX:" "$out" "[S24] and the tools beside it"
assert_not_contains "Xymon server" "$out" "[S24] and no server"
assert_not_contains "Its client" "$out" "[S24] nor a server's client section"
x verify XYMONHOME="$c"
assert_equal 0 "$rc" "[S24] verify, no part, on a client's tree: $out"
assert_contains "Xymon client: $c" "$out" "[S24] verify, no part, reads the client's tree XYMONHOME names"
assert_contains "ok: xymon-plugin" "$out" "[S24] and says it ok"
assert_contains "Your tools: $PREFIX" "$out" "[S24] and the tools beside it"

# An install cut short, a first one, before its VERSION: said by both.
mv "$d/VERSION" "$work/VERSION.kept"
echo "xymon-plugin in progress: xymon-plugin $(sh -c 'echo $$') first" > "$d/.xymon-plugin-in-progress"
x status --client XYMONHOME="$c"
assert_contains "xymon-plugin: cut short: ./xymon-plugin update --client xymon-plugin resumes it; this copy has $version" "$out" "[S15] status --client says an install cut short"
x verify --client XYMONHOME="$c"
assert_equal 3 "$rc" "[S30] verify --client of an install cut short exits 3: $out"
assert_contains "broken: xymon-plugin: $d is an install of xymon-plugin's client part cut short" "$out" "[S30] verify --client says an install cut short"
rm -f "$d/.xymon-plugin-in-progress"; mv "$work/VERSION.kept" "$d/VERSION"

# Detection, nothing named: the servers, then the standalone client trees
# found, each with what it holds; a server's own client tree within its
# server's section only; one in doubt said, not read.
s=$work/srv/server; server_tree "$s"; mkdir -p "$s/ext"
o=$work/own; server_tree "$o/server"; client_tree "$o/client"; mkdir -p "$o/server/ext"
echo "XYMONCLIENTHOME=\"$o/client\"" >> "$o/server/etc/xymonserver.cfg"
q=$work/doubt; server_tree "$q/server"; client_tree "$q/client"; mkdir -p "$q/server/ext"
export XYMON_PLUGINS_TREES="$s:$c:$o/server:$o/client:$q/client"
x status
[ "$rc" -eq 0 ] || fail "[S25] status with nothing named failed: $out"
assert_contains "Xymon server $s:" "$out" "[S25] status lists the server found"
assert_contains "Xymon client $c:" "$out" "[S25] status lists the standalone client tree found"
# The client tree's section alone: its lines until the next heading.
sec=$(printf '%s\n' "$out" | awk -v h="Xymon client $c:" '$0 == h { on = 1; next } on && /^[^ ]/ { on = 0 } on { print }')
assert_contains "  xymon-plugin: $version installed, off; this copy has $version" "$sec" "[S25] with what it holds"
assert_contains "Its client $o/client:" "$out" "[S25] a server's own client tree is said in its server's section"
assert_not_contains "Xymon client $o/client" "$out" "[S25] and not as a standalone client"
assert_contains "Xymon client $q/client:
  not read: $q/client may be a server's own client" "$out" "[S25] a client tree in doubt is said, not read"
[ "$(printf '%s\n' "$out" | grep -n "^Xymon server $s:" | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n "^Xymon client $c:" | cut -d: -f1)" ] \
	|| fail "[S15] the clients do not follow the servers: $out"
assert_contains "Your tools, $PREFIX:" "$out" "[S25] and the tools"
x status --client
assert_contains "Xymon client $c:" "$out" "[S25] status --client lists the client tree found"
assert_not_contains "Xymon server $s" "$out" "[S25] status --client lists no server"
assert_not_contains "Your tools" "$out" "[S25] status --client lists no tools"
x status --server
assert_not_contains "Xymon client" "$out" "[S25] status --server lists no standalone client"
# outdated reads the same trees (S32), and says the one in doubt, not
# read, as a VERSION it cannot compare: 7. A gh on PATH answers the
# release installed.
mkdir -p "$work/gh"; printf '#!/bin/sh\necho "xymon-plugin/v%s"\n' "$version" > "$work/gh/gh"; chmod 755 "$work/gh/gh"
PATH="$work/gh:$PATH" x outdated
assert_equal 7 "$rc" "[S32] outdated with a client tree in doubt: $out"
assert_contains "Xymon client $c:
  xymon-plugin: $version installed; up to date" "$out" "[S32] outdated reads the standalone client tree found"
assert_contains "Xymon client $q/client:
  not read: $q/client may be a server's own client" "$out" "[S32] and says the one in doubt, not read"
assert_not_contains "Xymon client $o/client" "$out" "[S32] a server's own client tree is no standalone client"
PATH="$work/gh:$PATH" x outdated --server
assert_not_contains "Xymon client" "$out" "[S32] outdated --server reads no client"
x verify
assert_equal 0 "$rc" "[S30] verify with nothing named, all ok: $out"
assert_contains "Xymon client: $c
ok: xymon-plugin" "$out" "[S30] verify covers the client tree found"
assert_contains "Xymon client: $q/client
  not read: " "$out" "[S30] verify says a client tree in doubt, not read"
echo changed >> "$d/xymon-plugin.8"
x verify --client
assert_equal 3 "$rc" "[S30] verify --client, nothing named, finds a file changed: $out"
assert_not_contains "Xymon server: " "$out" "[S30] verify --client covers no server"
cp "$work/page.kept" "$d/xymon-plugin.8"
export XYMON_PLUGINS_TREES=

# Refused, as by the other client verbs: a server's tree naming no client
# tree of its own (S36), a server's own client named directly, one in doubt.
for v in status verify; do
	x $v --client XYMONHOME="$s"
	[ "$rc" -ne 0 ] || fail "[S36] $v --client on a server's tree naming no client tree was taken"
	assert_contains "names no XYMONCLIENTHOME it can read" "$out" "[S36] $v --client on a server's tree naming no client tree is refused"
	x $v --client XYMONHOME="$o/client"
	[ "$rc" -ne 0 ] || fail "[S35] $v --client on a server's own client was taken"
	assert_contains "is the client tree of the Xymon server $o/server" "$out" "[S35] $v --client on a server's own client is refused"
	x $v XYMONHOME="$o/client"
	[ "$rc" -ne 0 ] || fail "[S25] $v, no part, on a server's own client was taken"
	assert_contains "name the server, ./xymon-plugin $v --xymon-home $o/server --server" "$out" "[S25] $v, no part, on a server's own client names the server"
	x $v --client XYMONHOME="$q/client"
	[ "$rc" -ne 0 ] || fail "[S35] $v --client on a client in doubt was taken"
	assert_contains "refused while in doubt" "$out" "[S35] $v --client on a client in doubt is refused"
done

pass "status, verify and outdated read a standalone client's tree as a server's, named or found, changing nothing: its plugins and versions, ok, broken, untidy and an install cut short; an ext/ not the person's read, a tree of another kind, a server's own client and one in doubt refused"
