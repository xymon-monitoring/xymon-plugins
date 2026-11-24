#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-own-client.sh
#
# A client part goes into a server's own client tree too (S36): named by
# its server, XYMONHOME=<server> --client, the tree its xymonserver.cfg
# names as XYMONCLIENTHOME, an absolute path spelt once, a variable
# refused; an ext/ that is a link, as Homebrew's, followed. The part's files go in that tree's ext/, @XYMONHOME@ that
# tree; its task, installed off, is linked from the server's tasks.d/ as
# NAME-client.cfg, beside a server part's NAME-server.cfg, its log in the
# server's logs; the server's tasks.cfg, not the client's
# clientlaunch.cfg, is the one read and touched. status and verify read
# the tree. Refused, nothing changed: the client tree named directly
# (giving the server's form), an XYMONCLIENTHOME naming nothing, a missing
# directory, one without a client's marks, or the server's own tree; a
# tree with no ext/ (giving the commands), whose read verbs find it empty;
# an ext/ owned by neither the server's ext/ owner nor root; and
# xymon-plugin, whose server copy manages that tree.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
work=$(cd "$work" && pwd -P)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME" "$work/man"

# A server and its own client tree, as Xymon's install lays them out.
s=$work/xymon/server c=$work/xymon/client
server_tree "$s"
mkdir -p "$s/ext" "$s/etc/tasks.d" "$c/bin" "$c/etc" "$c/ext"
printf 'XYMONCLIENTHOME="%s"\n' "$c" >> "$s/etc/xymonserver.cfg"
printf 'directory %s/etc/tasks.d\n' "$s" > "$s/etc/tasks.cfg"
: > "$c/bin/xymonclient.sh"; : > "$c/etc/xymonclient.cfg"
printf 'optional directory %s/etc/clientlaunch.d\n' "$c" > "$c/etc/clientlaunch.cfg"
cp "$s/etc/xymonserver.cfg" "$work/xymonserver.cfg"

# A checkout with two plugins of the test's own: oc, a client part with
# its task; both, a server part and a client part, each with its task.
r=$work/repo
mkdir -p "$r"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$r/"
mkdir -p "$r/plugins/oc" "$r/plugins/both"
printf 'name: oc\nversion: 1.0.0\nsummary: a test\nclient-files: check.sh\nclient-task: oc.tasks\n' > "$r/plugins/oc/PLUGIN"
printf '#!/bin/sh\nexit 0\n' > "$r/plugins/oc/check.sh"
printf '[oc-client]\n\tENVFILE @XYMONHOME@/etc/xymonclient.cfg\n\tCMD @XYMONHOME@/ext/oc/check.sh\n\tLOGFILE @LOGDIR@/oc-client.log\n\tINTERVAL 5m\n' > "$r/plugins/oc/oc.tasks"
printf 'name: both\nversion: 1.0.0\nsummary: a test\nserver-files: s.sh\nserver-task: s.tasks\nserver-manual: both.8\nclient-files: c.sh\nclient-task: c.tasks\nclient-manual: both.8\n' > "$r/plugins/both/PLUGIN"
printf '.TH BOTH 8\n' > "$r/plugins/both/both.8"
printf '#!/bin/sh\nexit 0\n' > "$r/plugins/both/s.sh"; cp "$r/plugins/both/s.sh" "$r/plugins/both/c.sh"
mkdir -p "$r/plugins/dep"
printf 'name: dep\nversion: 1.0.0\nsummary: a test\nclient-files: d.sh\nclient-needs: xymon-plugin\n' > "$r/plugins/dep/PLUGIN"
printf '#!/bin/sh\nexit 0\n' > "$r/plugins/dep/d.sh"
printf '[both-server]\n\tCMD @XYMONHOME@/ext/both/s.sh\n\tINTERVAL 5m\n' > "$r/plugins/both/s.tasks"
printf '[both-client]\n\tENVFILE @XYMONHOME@/etc/xymonclient.cfg\n\tCMD @XYMONHOME@/ext/both/c.sh\n\tLOGFILE @LOGDIR@/both-client.log\n\tINTERVAL 5m\n' > "$r/plugins/both/c.tasks"

# x ARG... -- the checkout's installer, off a terminal.
x() { rc=0; out=$("$r/xymon-plugin" "$@" MANDIR="$work/man" </dev/null 2>&1) || rc=$?; }
ok() { [ "$rc" -eq 0 ] || fail "$1 failed ($rc): $out"; }
refused() { [ "$rc" -ne 0 ] || fail "$1 was taken: $out"; }
dump() { "$XYMON_SRC/common/xymonlaunch" --config="$s/etc/tasks.cfg" --dump 2>/dev/null | grep '^\[' || true; }
link=$s/etc/tasks.d/oc-client.cfg

# Installed off, in the client tree, named by its server; the standalone
# client used last stays the one remembered.
mkdir -p "$XDG_CONFIG_HOME/xymon-plugin"; echo /a/standalone/client > "$XDG_CONFIG_HOME/xymon-plugin/installation-used-last-client"
x install --client oc XYMONHOME="$s"; ok "install --client named by the server"
assert_equal /a/standalone/client "$(cat "$XDG_CONFIG_HOME/xymon-plugin/installation-used-last-client")" "[S25] a server's own client tree is not remembered over the standalone client used last"
assert_contains "Target: $c (named by XYMONHOME, the client tree of the Xymon server $s), part: client" "$out" "[S36] the target is the server's client tree, said"
assert_file_exists "$c/ext/oc/tasks.cfg"
assert_contains "CMD $c/ext/oc/check.sh" "$(cat "$c/ext/oc/tasks.cfg")" "[S36] @XYMONHOME@ is the client tree"
assert_contains "LOGFILE \$XYMONSERVERLOGS/oc-client.log" "$(cat "$c/ext/oc/tasks.cfg")" "[S36] the log goes to the server's logs"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S36] the install made a link"
assert_contains "enable --client --xymon-home $s oc turns it on" "$out" "[S36] and gives the command, with the server"

# enable: the link from the server's tasks.d/, the server's tasks.cfg read
# and touched, the client's clientlaunch.d/ untouched.
touch -t 200001010000 "$s/etc/tasks.cfg"; : > "$work/ref"; touch -t 200101010000 "$work/ref"
x enable --client oc XYMONHOME="$s"; ok "enable --client"
assert_equal "$c/ext/oc/tasks.cfg" "$(readlink "$link")" "[S36] the link in the server's tasks.d/ names the task file in the client tree"
[ -n "$(find "$s/etc/tasks.cfg" -newer "$work/ref")" ] || fail "[S36] enable did not touch the server's tasks.cfg"
[ ! -e "$c/etc/clientlaunch.d" ] || fail "[S36] enable made the client's clientlaunch.d/"
assert_contains "[oc-client]" "$(dump)" "[S36] the server's xymonlaunch has the task"
x status --client XYMONHOME="$s"; ok "status --client"
assert_contains "oc: 1.0.0 installed, on" "$out" "[S36] status reads the tree"
x verify --client XYMONHOME="$s"; ok "verify --client"
assert_contains "ok: oc" "$out" "[S36] verify reads the tree"

# Both parts of one plugin: each its tree, each its task, side by side.
x install --server both XYMONHOME="$s"; ok "install --server both"
x install --client both XYMONHOME="$s"; ok "install --client both"
x enable --server both XYMONHOME="$s"; ok "enable --server both"
x enable --client both XYMONHOME="$s"; ok "enable --client both"
assert_equal "$s/ext/both/tasks.cfg" "$(readlink "$s/etc/tasks.d/both-server.cfg")" "[S36] the server part's link"
assert_equal "$c/ext/both/tasks.cfg" "$(readlink "$s/etc/tasks.d/both-client.cfg")" "[S36] the client part's link beside it"
d=$(dump)
assert_contains "[both-server]" "$d" "[S36] xymonlaunch has the server part's task"
assert_contains "[both-client]" "$d" "[S36] and the client part's, apart"
x remove --client both XYMONHOME="$s"; ok "remove --client both"
[ -L "$s/etc/tasks.d/both-server.cfg" ] || fail "[S36] remove --client took the server part's link"
{ [ -e "$s/etc/tasks.d/both-client.cfg" ] || [ -L "$s/etc/tasks.d/both-client.cfg" ]; } && fail "[S36] remove --client left the client part's link"
[ -d "$s/ext/both" ] || fail "[S36] remove --client took the server part"
# One manual page for both parts (S20): the link the first install made,
# the other's install leaving it, said nothing of; the part removed first
# pointing it at the other's copy, the last taking it.
pg=$work/man/man8/both.8
assert_equal "$s/ext/both/both.8" "$(readlink "$pg")" "[S20] the server part's page linked"
x install --client both XYMONHOME="$s"; ok "install --client both, the page shared"
assert_not_contains "another's" "$out" "[S20] the client part's install leaves the shared page, saying nothing"
assert_equal "$s/ext/both/both.8" "$(readlink "$pg")" "[S20] the link the first install made kept"
x remove --server both XYMONHOME="$s"; ok "remove --server both, the client part staying"
assert_equal "$c/ext/both/both.8" "$(readlink "$pg")" "[S20] the page then the client part's copy"
x remove --client both XYMONHOME="$s"; ok "remove --client both, the last"
{ [ -e "$pg" ] || [ -L "$pg" ]; } && fail "[S20] the last part removed left the page's link"
x install --server both XYMONHOME="$s"; ok "install --server both again"

# The server's tasks.cfg is the one enable reads: one that does not read
# tasks.d/, or that has a task of the name already, refused (S13, S6).
x disable --client oc XYMONHOME="$s"; ok "disable --client"
cp "$s/etc/tasks.cfg" "$work/tasks.cfg"
echo '# no directory line' > "$s/etc/tasks.cfg"
x enable --client oc XYMONHOME="$s"; refused "enable --client, the server's tasks.cfg not reading tasks.d/"
assert_contains "$s/etc/tasks.cfg does not read tasks.d/" "$out" "[S36] the server's tasks.cfg is the one read, and named"
cp "$work/tasks.cfg" "$s/etc/tasks.cfg"; printf '[oc-client]\n\tCMD /bin/true\n' >> "$s/etc/tasks.cfg"
x enable --client oc XYMONHOME="$s"; refused "enable --client, a task of its name in the server's tasks.cfg"
assert_contains "reads a task named [oc-client] already, in $s/etc/tasks.cfg" "$out" "[S36] a task of its name the server's launcher reads: refused"
cp "$work/tasks.cfg" "$s/etc/tasks.cfg"
x enable --client oc XYMONHOME="$s"; ok "enable --client again"

# The plugin's directory removed by hand, its task on: the link left in
# the server's tasks.d/, named so by verify, taken by clean (S30, S31).
cp -R "$c/ext/oc" "$work/oc.kept"; rm -rf "$c/ext/oc"
x verify --client XYMONHOME="$s"
assert_contains "$s/etc/tasks.d/oc-client.cfg" "$out" "[S36] verify names the task link left in the server's tasks.d/"
x clean --client --all --yes XYMONHOME="$s"; ok "clean --client"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S36] clean --client left the task link in the server's tasks.d/"
cp -R "$work/oc.kept" "$c/ext/oc"
x enable --client oc XYMONHOME="$s"; ok "enable --client, the directory back"

# disable and remove of oc.
x disable --client oc XYMONHOME="$s"; ok "disable --client"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S36] disable left the link"
x remove --client oc XYMONHOME="$s"; ok "remove --client"
[ ! -e "$c/ext/oc" ] || fail "[S36] remove left the directory"

# The client tree named directly: refused, the server's form given.
x install --client oc XYMONHOME="$c"; refused "install --client named by the client tree"
assert_contains "is the client tree of the Xymon server $s: name the server, ./xymon-plugin install --client --xymon-home $s" "$out" "[S36] and gives the server's form"

# xymon-plugin: its client part does not go there. Named, refused before
# anything changes, another plugin named with it untouched; a copy left
# is said with the commands that remove it, which do; not named, passed
# over, said once.
for v in install update remove enable disable; do
	x $v --client xymon-plugin XYMONHOME="$s"; refused "$v --client xymon-plugin on a server"
	assert_contains "xymon-plugin's client part does not go in the client tree of the Xymon server $s" "$out" "[S36] $v of xymon-plugin: refused, saying why"
	assert_not_contains "./xymon-plugin install --client" "$out" "[S36] $v of xymon-plugin: no command given that is refused too"
done
x install --client oc xymon-plugin XYMONHOME="$s"; refused "install --client oc xymon-plugin on a server"
[ ! -e "$c/ext/oc" ] || fail "[S36] oc named with xymon-plugin was installed before the refusal"
mkdir -p "$c/ext/xymon-plugin" "$c/etc/clientlaunch.d" "$work/man/man8"
cp "$ROOT/plugins/xymon-plugin/PLUGIN" "$c/ext/xymon-plugin/PLUGIN"; echo xymon-plugin/v0.0.1 > "$c/ext/xymon-plugin/VERSION"
: > "$c/ext/xymon-plugin/tasks.cfg"; : > "$c/ext/xymon-plugin/xymon-plugin.8"
ln -s "$c/ext/xymon-plugin/tasks.cfg" "$c/etc/clientlaunch.d/xymon-plugin-client.cfg"
ln -s "$c/ext/xymon-plugin/xymon-plugin.8" "$work/man/man8/xymon-plugin.8"
x remove --client xymon-plugin XYMONHOME="$s"; refused "remove --client xymon-plugin on a server"
assert_contains "rm -rf $c/ext/xymon-plugin $c/etc/clientlaunch.d/xymon-plugin-client.cfg" "$out" "[S36] a copy left: the directory's removal given, and its link in clientlaunch.d/"
assert_contains "./xymon-plugin clean --client --xymon-home $s xymon-plugin" "$out" "[S36] and clean for what it left elsewhere"
rm -rf "$c/ext/xymon-plugin" "$c/etc/clientlaunch.d/xymon-plugin-client.cfg"
x clean --client xymon-plugin XYMONHOME="$s" --yes; ok "clean --client xymon-plugin, the copy removed"
[ ! -L "$work/man/man8/xymon-plugin.8" ] || fail "[S36] clean left the copy's manual page link"
# A need on xymon-plugin: met by the server's copy, refused while the
# server has none; the server's copy, needed there, not removed.
x install --client dep XYMONHOME="$s"; refused "install --client of a plugin needing xymon-plugin, the server without it"
assert_contains "dep needs xymon-plugin, whose part in the client tree of a Xymon server is the server's copy, which $s has not" "$out" "[S36] refused, saying the server's copy is missing"
[ ! -e "$c/ext/dep" ] || fail "[S36] dep installed though its need is unmet"
x install --server xymon-plugin XYMONHOME="$s"; ok "install --server xymon-plugin"
x install --client dep XYMONHOME="$s"; ok "install --client of a plugin needing xymon-plugin, on a server"
assert_contains "xymon-plugin is passed over: the server's copy stands for its client part" "$out" "[S36] a need on xymon-plugin met by the server's copy, said"
assert_file_exists "$c/ext/dep/VERSION"
[ ! -e "$c/ext/xymon-plugin" ] || fail "[S36] the need installed xymon-plugin's client part in the server's client tree"
x remove --server xymon-plugin XYMONHOME="$s"; refused "remove --server xymon-plugin, needed in the server's client tree"
assert_contains "xymon-plugin is needed by dep, in the client tree of this server" "$out" "[S36] and says by what"
x remove --client dep XYMONHOME="$s"; ok "remove --client dep"
x install --client --all XYMONHOME="$s"; ok "install --client --all on a server"
assert_equal 1 "$(printf '%s\n' "$out" | grep -c 'xymon-plugin is passed over')" "[S36] --all: xymon-plugin passed over, said once"
x remove --client --all XYMONHOME="$s"; ok "remove --client --all on a server"
x remove --server xymon-plugin XYMONHOME="$s"; ok "remove --server xymon-plugin, needed no more"
rmdir "$c/etc/clientlaunch.d"

# XYMONCLIENTHOME: a variable is refused, as nothing here reads it; and a
# client tree named directly, a server found naming its client tree with
# a variable, is in doubt. Then naming nothing, a relative path, a missing
# directory, no client's marks, the server's own tree.
sed "s|^XYMONCLIENTHOME=.*|XYMONCLIENTHOME=\"\$XYMONTOPDIR/client\"|" "$work/xymonserver.cfg" > "$s/etc/xymonserver.cfg"
x install --client oc XYMONHOME="$s"; refused "install --client, XYMONCLIENTHOME a variable"
assert_contains "XYMONCLIENTHOME, \$XYMONTOPDIR/client, names a variable, which this command does not read: write the client tree's path itself" "$out" "[S36] a variable: refused, saying what was read"
o=$work/elsewhere/client
mkdir -p "$o/bin" "$o/etc" "$o/ext"; : > "$o/bin/xymonclient.sh"; : > "$o/etc/xymonclient.cfg"
XYMON_PLUGINS_TREES=$s x install --client oc XYMONHOME="$o"; refused "install --client in a client tree, a server found naming its own with a variable"
assert_contains "the Xymon server $s names its client tree with a variable, which this command does not read; refused while in doubt" "$out" "[S25] a server found naming its client tree with a variable: in doubt"
cp "$work/xymonserver.cfg" "$s/etc/xymonserver.cfg"
case_refused() {   # case_refused LINE WHY EXPECTED
	{ grep -v '^XYMONCLIENTHOME=' "$work/xymonserver.cfg"; [ -z "$1" ] || printf '%s\n' "$1"; } > "$s/etc/xymonserver.cfg"
	x install --client oc XYMONHOME="$s"; refused "install --client, $2"
	assert_contains "$3" "$out" "[S36] $2: refused, saying what was read"
	[ ! -e "$c/ext/oc" ] || fail "[S36] $2: installed all the same"
}
case_refused "" "no XYMONCLIENTHOME" "names no XYMONCLIENTHOME it can read"
case_refused "XYMONCLIENTHOME=\"client\"" "a relative path" "XYMONCLIENTHOME, client, is not an absolute path"
case_refused "XYMONCLIENTHOME=\"$work/none\"" "a missing directory" "$work/none, is not there"
mkdir -p "$work/plain"
case_refused "XYMONCLIENTHOME=\"$work/plain\"" "no client's marks" "is no Xymon client's tree"
case_refused "XYMONCLIENTHOME=\"$s\"" "the server's own tree" "is the server's own tree"
mkdir -p "$work/other/bin" "$work/other/etc"
: > "$work/other/bin/xymond"; : > "$work/other/etc/xymonserver.cfg"; : > "$work/other/bin/xymonclient.sh"; : > "$work/other/etc/xymonclient.cfg"
case_refused "XYMONCLIENTHOME=\"$work/other\"" "a tree with both pairs of marks" "$work/other, is a Xymon server's tree"
cp "$work/xymonserver.cfg" "$s/etc/xymonserver.cfg"

# A trailing / and a /.: taken off, as the server's XYMONHOME has them,
# nothing written naming the tree otherwise.
for v in "$c/" "$c/."; do
	{ grep -v '^XYMONCLIENTHOME=' "$work/xymonserver.cfg"; printf 'XYMONCLIENTHOME="%s"\n' "$v"; } > "$s/etc/xymonserver.cfg"
	x install --client oc XYMONHOME="$s"; ok "install --client, XYMONCLIENTHOME $v"
	assert_contains "CMD $c/ext/oc/check.sh" "$(cat "$c/ext/oc/tasks.cfg")" "[S36] XYMONCLIENTHOME $v: the tree spelt once in the task file"
	x enable --client oc XYMONHOME="$s"; ok "enable --client, XYMONCLIENTHOME $v"
	assert_equal "$c/ext/oc/tasks.cfg" "$(readlink "$link")" "[S36] XYMONCLIENTHOME $v: the link names the tree spelt once"
	cp "$work/xymonserver.cfg" "$s/etc/xymonserver.cfg"
	x remove --client oc XYMONHOME="$s"; ok "remove --client, XYMONCLIENTHOME respelt"
	{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S36] XYMONCLIENTHOME $v, respelt: remove left the link"
done

# Homebrew's layout: the package's opt/ a link to its current version in
# Cellar/, ext/ (the server's and its client's) links into var/. Accepted,
# the files in var/, and every path written through opt/, not the version,
# which the next upgrade replaces.
hb=$work/hb
mkdir -p "$hb/Cellar/xs/1.0/server/bin" "$hb/Cellar/xs/1.0/server/etc/tasks.d" "$hb/Cellar/xs/1.0/client/bin" "$hb/Cellar/xs/1.0/client/etc" "$hb/var/ext" "$hb/var/client/ext" "$hb/opt"
ln -s "$hb/Cellar/xs/1.0" "$hb/opt/xs"
hs=$hb/opt/xs/server hc=$hb/opt/xs/client
: > "$hs/bin/xymond"; printf 'XYMONCLIENTHOME="%s"\n' "$hc" > "$hs/etc/xymonserver.cfg"
printf 'directory %s/etc/tasks.d\n' "$hs" > "$hs/etc/tasks.cfg"
: > "$hc/bin/xymonclient.sh"; : > "$hc/etc/xymonclient.cfg"
ln -s "$hb/var/ext" "$hs/ext"; ln -s "$hb/var/client/ext" "$hc/ext"
x install --client oc XYMONHOME="$hs"; ok "install --client on Homebrew's layout"
assert_file_exists "$hb/var/client/ext/oc/tasks.cfg"
assert_contains "CMD $hc/ext/oc/check.sh" "$(cat "$hb/var/client/ext/oc/tasks.cfg")" "[S36] Homebrew: the task file names the tree through opt/"
assert_not_contains "Cellar" "$(cat "$hb/var/client/ext/oc/tasks.cfg" "$hb/var/client/ext/oc/MANIFEST")" "[S36] Homebrew: nothing written names the version"
x enable --client oc XYMONHOME="$hs"; ok "enable --client on Homebrew's layout"
assert_equal "$hc/ext/oc/tasks.cfg" "$(readlink "$hs/etc/tasks.d/oc-client.cfg")" "[S36] Homebrew: the link names the task file through opt/"
x status --client XYMONHOME="$hs"; ok "status --client on Homebrew's layout"
assert_contains "oc: 1.0.0 installed, on" "$out" "[S36] Homebrew: status reads through the linked ext/"
x remove --client oc XYMONHOME="$hs"; ok "remove --client on Homebrew's layout"
[ ! -e "$hb/var/client/ext/oc" ] || fail "[S36] Homebrew: remove left the directory"

# The server without ext/: its install broken, said, nothing guessed.
mv "$s/ext" "$work/sext.away"
x install --client oc XYMONHOME="$s"; refused "install --client, the server without ext/"
assert_contains "$s has no directory ext/, which every Xymon server install makes: its install is incomplete" "$out" "[S36] the server without ext/: refused, saying so"
assert_not_contains "cannot access" "$out" "[S36] the server without ext/: no raw error"
mv "$work/sext.away" "$s/ext"

# No ext/: refused, the commands given; the read verbs find it empty.
mv "$c/ext" "$work/ext.away"
x install --client oc XYMONHOME="$s"; refused "install --client, no ext/"
assert_contains "$c has no directory ext/" "$out" "[S36] no ext/: refused, saying so"
assert_contains "mkdir $c/ext && chown" "$out" "[S36] and gives the commands"
x status --client XYMONHOME="$s"; ok "status --client, no ext/"
mkdir -p "$work/net"; printf '#!/bin/sh\necho "[]"\n' > "$work/net/curl"; chmod 755 "$work/net/curl"
op=$PATH; PATH=$work/net:$PATH
XYMON_PLUGINS_NO_GH=1 x outdated --client XYMONHOME="$s"
PATH=$op
ok "outdated --client, no ext/"
x verify --client XYMONHOME="$s"; ok "verify --client, no ext/"
mv "$work/ext.away" "$c/ext"

# An update in that tree keeps the task on and the edited file; cut short
# after the directory is emptied, the next resumes it (S7).
x install --client oc XYMONHOME="$s"; ok "install --client, to update"
x enable --client oc XYMONHOME="$s"; ok "enable --client, to update"
sed 's/INTERVAL 5m/INTERVAL 1h/' "$c/ext/oc/tasks.cfg" > "$work/edited"; cat "$work/edited" > "$c/ext/oc/tasks.cfg"
x update --client oc XYMONHOME="$s"; ok "update --client"
assert_contains "INTERVAL 1h" "$(cat "$c/ext/oc/tasks.cfg")" "[S36] an update keeps the edited task file"
assert_equal "$c/ext/oc/tasks.cfg" "$(readlink "$link")" "[S36] and the task on"
cut=$work/cut; mkdir -p "$cut"; cp -R "$r/xymon-plugin" "$r/LICENSE" "$r/plugins" "$cut/"
# shellcheck disable=SC2016 # the installer's line, as it is written
line='	fresh "$dir" "$keep" || exit 1'
awk -v l="$line" '{ print } $0 == l { print "\tkill -TERM $$" }' "$r/plugins/xymon-plugin/xymon-plugin" > "$cut/plugins/xymon-plugin/xymon-plugin"
rc=0; out=$("$cut/xymon-plugin" update --client oc XYMONHOME="$s" MANDIR="$work/man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S7] the cut update succeeded: $out"
x update --client oc XYMONHOME="$s"; ok "update --client resuming"
assert_contains "Resuming the install of oc cut short" "$out" "[S36] the next update resumes"
assert_contains "INTERVAL 1h" "$(cat "$c/ext/oc/tasks.cfg")" "[S36] with the edited task file"
assert_contains "LOGFILE \$XYMONSERVERLOGS/oc-client.log" "$(cat "$c/ext/oc/tasks.cfg.new" 2>/dev/null || cat "$c/ext/oc/tasks.cfg")" "[S36] @LOGDIR@ the server's logs after a resume"
rm -f "$c/ext/oc/tasks.cfg.new"

# --server on that server leaves the client's links alone: verify and
# clean neither say nor take them.
x verify --server XYMONHOME="$s"
assert_not_contains "oc-client.cfg" "$out" "[S36] verify --server says nothing of the client part's link"
x clean --server --all --yes XYMONHOME="$s"; ok "clean --server --all"
[ -L "$link" ] || fail "[S36] clean --server took the client part's link"

# XYMONCLIENTHOME respelt through a link to the same tree: links are
# compared as written, so verify says the task link points elsewhere, with
# what puts it right.
ln -s "$c" "$work/respelt"
{ grep -v '^XYMONCLIENTHOME=' "$work/xymonserver.cfg"; printf 'XYMONCLIENTHOME="%s"\n' "$work/respelt"; } > "$s/etc/xymonserver.cfg"
x verify --client oc XYMONHOME="$s"
assert_contains "points to $c/ext/oc/tasks.cfg, not its task file: ./xymon-plugin disable --client oc, then enable" "$out" "[S36] respelt: verify says the link as written, and what puts it right"
cp "$work/xymonserver.cfg" "$s/etc/xymonserver.cfg"
x remove --client oc XYMONHOME="$s"; ok "remove --client, spelt back"

# XYMONCLIENTHOME's rarer forms: blanks after it, export before it, set in
# xymonserver.d/ last.
for form in "XYMONCLIENTHOME=\"$c\"   " "export XYMONCLIENTHOME=$c # mine" "d"; do
	grep -v '^XYMONCLIENTHOME=' "$work/xymonserver.cfg" > "$s/etc/xymonserver.cfg"
	if [ "$form" = d ]; then
		printf 'XYMONCLIENTHOME="%s/none"\n' "$work" >> "$s/etc/xymonserver.cfg"
		mkdir -p "$s/etc/xymonserver.d"; printf 'XYMONCLIENTHOME="%s"\n' "$c" > "$s/etc/xymonserver.d/client.cfg"
	else
		printf '%s\n' "$form" >> "$s/etc/xymonserver.cfg"
	fi
	x install --client oc XYMONHOME="$s"; ok "install --client, XYMONCLIENTHOME as: $form"
	x remove --client oc XYMONHOME="$s"; ok "remove --client, XYMONCLIENTHOME as: $form"
	rm -rf "$s/etc/xymonserver.d"
done
cp "$work/xymonserver.cfg" "$s/etc/xymonserver.cfg"

# A link left in the client's clientlaunch.d/, from its life as a
# standalone client, which the server's launcher does not read: said by
# verify, taken by clean.
x install --client oc XYMONHOME="$s"; ok "install --client, for clientlaunch.d"
mkdir -p "$c/etc/clientlaunch.d"; ln -s "$c/ext/oc/tasks.cfg" "$c/etc/clientlaunch.d/oc-client.cfg"
x verify --client XYMONHOME="$s"
assert_contains "a task link in clientlaunch.d/, which the server's xymonlaunch does not read" "$out" "[S36] verify says a link left in clientlaunch.d/"
assert_contains "clean --client --xymon-home $s --all" "$out" "[S36] with clean, the server named"
ln -s "$c/ext/admin.sh" "$c/etc/clientlaunch.d/admin.cfg"; ln -s "$c/ext/admin.sh" "$c/etc/clientlaunch.d/mine-client.cfg"
x clean --client --all --yes XYMONHOME="$s"; ok "clean --client, clientlaunch.d/"
[ ! -L "$c/etc/clientlaunch.d/oc-client.cfg" ] || fail "[S36] clean left the link in clientlaunch.d/"
for f in admin.cfg mine-client.cfg; do
	[ -L "$c/etc/clientlaunch.d/$f" ] || fail "[S36] clean took the administrator's own link $f in clientlaunch.d/"
done
rm -f "$c/etc/clientlaunch.d/admin.cfg" "$c/etc/clientlaunch.d/mine-client.cfg"
x remove --client oc XYMONHOME="$s"; ok "remove --client, after clientlaunch.d"
rmdir "$c/etc/clientlaunch.d"

# The client tree named directly with a linked ext/, as Homebrew's: the
# server's form given, the names kept, the path quoted.
x install --client oc XYMONHOME="$hc"; refused "install --client named by Homebrew's client tree"
assert_contains "is the client tree of the Xymon server $hs: name the server, ./xymon-plugin install --client --xymon-home $hs oc" "$out" "[S36] Homebrew's client tree named: the server's form, the names kept"
# A dangling ext/ link: the directory it names to make.
mv "$hb/var/client/ext" "$hb/var/client/ext.away"
x install --client oc XYMONHOME="$hs"; refused "install --client, a dangling ext/ link"
assert_contains "mkdir -p $hb/var/client/ext" "$out" "[S36] a dangling ext/ link: the directory it names to make"
mv "$hb/var/client/ext.away" "$hb/var/client/ext"
# An upgrade: the version replaced, opt/ repointed; nothing named the old.
x install --client oc XYMONHOME="$hs"; ok "install --client, before an upgrade"
x enable --client oc XYMONHOME="$hs"; ok "enable --client, before an upgrade"
cp -R "$hb/Cellar/xs/1.0" "$hb/Cellar/xs/1.1"; rm "$hb/opt/xs"; ln -s "$hb/Cellar/xs/1.1" "$hb/opt/xs"; rm -rf "$hb/Cellar/xs/1.0"
x verify --client XYMONHOME="$hs"; ok "verify --client after an upgrade"
assert_contains "ok: oc" "$out" "[S36] Homebrew: after an upgrade, the install as it was"
x update --client oc XYMONHOME="$hs"; ok "update --client after an upgrade"
x remove --client oc XYMONHOME="$hs"; ok "remove --client after an upgrade"
{ [ -e "$hs/etc/tasks.d/oc-client.cfg" ] || [ -L "$hs/etc/tasks.d/oc-client.cfg" ]; } && fail "[S36] Homebrew: remove after an upgrade left the link"

# A path with a blank: the commands printed quote it.
sp="$work/a b"; mkdir -p "$sp/client/bin" "$sp/client/etc"; : > "$sp/client/bin/xymonclient.sh"; : > "$sp/client/etc/xymonclient.cfg"
{ grep -v '^XYMONCLIENTHOME=' "$work/xymonserver.cfg"; printf 'XYMONCLIENTHOME="%s/client"\n' "$sp"; } > "$s/etc/xymonserver.cfg"
x install --client oc XYMONHOME="$s"; refused "install --client, a client tree with a blank and no ext/"
assert_contains "mkdir '$sp/client/ext'" "$out" "[S36] the printed command quotes the path"
cp "$work/xymonserver.cfg" "$s/etc/xymonserver.cfg"

# No XYMONHOME, off a terminal: the server's form said too.
x install --client oc; refused "install --client with no XYMONHOME"
assert_contains "or a server's for its own client tree" "$out" "[S36] the server's form said"

# A need on xymon-plugin written xymon-plugin:client keeps the server's
# copy too.
x install --server xymon-plugin XYMONHOME="$s"; ok "install --server xymon-plugin, for dep2"
mkdir -p "$r/plugins/dep2"
printf 'name: dep2\nversion: 1.0.0\nsummary: a test\nclient-files: d.sh\nclient-needs: xymon-plugin:client\n' > "$r/plugins/dep2/PLUGIN"
cp "$r/plugins/dep/d.sh" "$r/plugins/dep2/d.sh"
x install --client dep2 XYMONHOME="$s"; ok "install --client dep2"
x remove --server xymon-plugin XYMONHOME="$s"; refused "remove --server xymon-plugin, needed as xymon-plugin:client"
assert_contains "xymon-plugin is needed by dep2" "$out" "[S36] a need written NAME:PART read as every need is"
x remove --client dep2 XYMONHOME="$s"; ok "remove --client dep2"
x remove --server xymon-plugin XYMONHOME="$s"; ok "remove --server xymon-plugin, after dep2"
rm -rf "$r/plugins/dep2"

# The client tree's ext/ the server's own under another name: refused.
mv "$c/ext" "$work/cext.away"; ln -s "$s/ext" "$c/ext"
x install --client oc XYMONHOME="$s"; refused "install --client, the client's ext/ the server's"
assert_contains "is the server's own ext/" "$out" "[S36] the server's ext/ under another name: refused"
rm "$c/ext"; mv "$work/cext.away" "$c/ext"

# An ext/ owned by another: refused, the chown given. The owner is read
# through ls, here a stand-in, as a test is not root.
mkdir -p "$work/bin"
cat > "$work/bin/ls" <<SH
#!/bin/sh
for a; do last=\$a; done
if [ "\$last" = "$c/ext" ] || [ "\$last" = "$hc/ext" ]; then $(command -v ls) "\$@" | awk -v u="\${FAKEUID:-4242}" '{ \$3 = u; print }'
elif [ -n "\${FAKETD:-}" ] && [ "\$last" = "$s/etc/tasks.d" ]; then $(command -v ls) "\$@" | awk -v u="\$FAKETD" '{ \$3 = u; print }'
else exec $(command -v ls) "\$@"; fi
SH
chmod 755 "$work/bin/ls"
op=$PATH; PATH=$work/bin:$PATH
x install --client oc XYMONHOME="$s"
PATH=$op
refused "install --client, ext/ another's"
assert_contains "$c/ext is 4242's, not $(id -un)'s, who owns the server's $s/etc/tasks.d" "$out" "[S36] an ext/ owned by another than the server's tasks.d/: refused, saying why"
assert_contains "make them one owner's" "$out" "[S36] and what puts it right"
[ ! -e "$c/ext/oc" ] || fail "[S36] ext/ another's: installed all the same"
# Root's both, as Debian has them: accepted for the tasks; but the person
# running it does not own it, as S35 has it: run by root.
op=$PATH; PATH=$work/bin:$PATH
FAKEUID=0 FAKETD=0 x install --client oc XYMONHOME="$s"
PATH=$op
refused "install --client, ext/ and tasks.d/ root's, run by another"
assert_not_contains "who owns the server's" "$out" "[S36] ext/ and tasks.d/ of one owner: the tasks' owner allowed"
assert_contains "run this as 0" "$out" "[S35] and is run by its owner"
# Root's ext/, the server's tasks.d/ another's: refused, root not taken
# apart, as a link to any root's directory would otherwise pass.
op=$PATH; PATH=$work/bin:$PATH
FAKEUID=0 x install --client oc XYMONHOME="$s"
PATH=$op
refused "install --client, ext/ root's, the server's tasks.d/ not"
assert_contains "$c/ext is 0's, not $(id -un)'s, who owns the server's" "$out" "[S36] root's ext/ held to the server's tasks.d/ owner too"
# A linked ext/ whose target another owns, as on a layout given another's
# directory: refused, no chown given for what the link names.
op=$PATH; PATH=$work/bin:$PATH
x install --client oc XYMONHOME="$hs"
PATH=$op
refused "install --client, a linked ext/ another's"
assert_contains "$hc/ext is a link to" "$out" "[S36] a linked ext/ another's: refused, saying so"
assert_not_contains "chown" "$out" "[S36] and no chown for what the link names"

pass "a client part in a server's own client tree, named by its server: files in that tree, its task linked from the server's tasks.d/ as NAME-client.cfg beside NAME-server.cfg, the server's tasks.cfg read and touched, its log in the server's; status and verify read it; refused, saying what was read: the client tree named directly, XYMONCLIENTHOME naming nothing, a missing or unmarked tree or the server's own, no ext/ (read verbs finding it empty), an ext/ another's, xymon-plugin"
