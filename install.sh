#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install, update and remove the plugins, on the Xymon server or on another
# machine, with nothing but a POSIX shell and the usual tools: no make.
#
#   XYMONHOME=/usr/lib/xymon/server ./install.sh install-server [PLUGIN...]  on the Xymon server
#   ./install.sh install-tools [PLUGIN...]       on your own machine, under PREFIX (~/.local)
#   ./install.sh enable-server|disable-server [PLUGIN...]  a server task on or off
#   ./install.sh uninstall-server|uninstall-tools [PLUGIN...]
#   ./install.sh venv-server|venv-tools          the virtualenv beside the plugins
#
# The server actions are also spelt without -server, their names before the
# tools had one. install-client and its kin are refused, naming the tools
# action: "client" is Xymon's, the monitored host, and the action of that
# name will install a client extension there once one is here.
#
# With no PLUGIN, every plugin of that side. A server plugin whose xymon:
# line names a newer Xymon than $XYMONHOME/bin/xymon --version gives is
# refused, unless --force. A development version, 4.3.32-dev, comes after
# 4.3.31 and before 4.3.32: a plugin that needs 4.3.32 installs on it with
# a warning, as it may lack what 4.3.32 brought. A plugin that needs another
# installs it first, and an uninstall is refused while one installed needs
# the plugin removed. An install starts nothing: a server task is on when
# tasks.d/PLUGIN, a link to it, is there, which enable-server makes and
# disable-server removes. Running an install again updates: each plugin's
# directory is replaced as a whole, and the admin's task files, whether each
# is on, web server snippets and data are kept. Settings come from the environment, or as
# NAME=value arguments: XYMONHOME, PREFIX, MANDIR (/usr/share/man), DESTDIR,
# which stages either side for a package, and PYTHON, the Python a
# virtualenv is made with.
#
# What each plugin installs is in its plugins/NAME/PLUGIN file. On a server
# the plugins go under $XYMONHOME/ext/, one directory each, and a plugin that
# needs another finds it beside itself; elsewhere they go under
# $PREFIX/libexec/xymon-plugins/ the same way, with a command per plugin in
# $PREFIX/bin. Each records its version beside its files, in VERSION, and
# the virtualenv they share sits beside them, as venv/. Every path is
# quoted, and escaped before it reaches sed: a directory with a space, an &
# or a | in its name is a directory like any other.

ROOT=$(cd "$(dirname "$0")" && pwd)

die() { echo "install.sh: $*" >&2; exit 1; }
usage() {
	echo "usage: ./install.sh install-server|install-tools|enable-server|disable-server|uninstall-server|uninstall-tools|venv-server|venv-tools [--force] [PLUGIN...] [NAME=value...]" >&2
	exit 2
}

[ $# -ge 1 ] || usage
ACTION=$1; shift
NAMES=
FORCE=
for a in "$@"; do
	case $a in
		--force) FORCE=1 ;;
		-*) usage ;;
		*=*) export "$a" ;;
		*) NAMES="$NAMES $a" ;;
	esac
done

XYMONHOME=${XYMONHOME:-}
DESTDIR=${DESTDIR:-}
MANDIR=${MANDIR:-/usr/share/man}
PREFIX=${PREFIX:-$HOME/.local}
# PYTHON given is also the one an install makes the virtualenv from, in
# place of its search for one.
PYTHON_GIVEN=${PYTHON:-}
PYTHON=${PYTHON:-python3}

EXTROOT=$DESTDIR$XYMONHOME/ext
ETC=$DESTDIR$XYMONHOME/etc
TASKDIR=$ETC/tasks.d
TOOLSROOT=$DESTDIR$PREFIX/libexec/xymon-plugins
BIN=$DESTDIR$PREFIX/bin
TOOLSMAN1=$DESTDIR$PREFIX/share/man/man1
# What other machines install from, which the API serves at /plugins: each
# plugin installed on the server stages its directory here, as in the
# repository, beside this script and LICENSE.
DIST=$EXTROOT/xymon-plugins-dist

# field PLUGIN KEY -- the value of KEY in the plugin's PLUGIN file, one line
# for each time the key appears.
field() { sed -n "s/^$2: //p" "$ROOT/plugins/$1/PLUGIN"; }

# sedesc TEXT -- TEXT escaped for the right-hand side of a sed s|||.
sedesc() { printf '%s\n' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# say PLUGIN KEY -- print the plugin's message KEY, its placeholders filled.
say() {
	field "$1" "$2" | sed -e "s|@ETC@|$(sedesc "$ETC")|g" -e "s|@TASKDIR@|$(sedesc "$TASKDIR")|g" \
		-e "s|@XYMONHOME@|$(sedesc "$XYMONHOME")|g"
}

# Every plugin, by the directories under plugins/ that hold a PLUGIN file.
all_plugins() {
	for f in "$ROOT"/plugins/*/PLUGIN; do
		[ -e "$f" ] && basename "$(dirname "$f")"
	done
}

# known PLUGIN -- refuse a name that is not a plugin here, or that could
# name a directory other than one plugin's.
known() {
	case $1 in ""|*/*|.|..) die "not a plugin name: '$1'" ;; esac
	[ -f "$ROOT/plugins/$1/PLUGIN" ] || die "no plugin $1 here: the plugins are $(echo $(all_plugins))"
}

# depth PLUGIN -- how many plugins deep it stands on: 0 for one that needs
# none. Uninstalling every plugin goes from the deepest up.
depth() {
	d=0
	for n in $(field "$1" needs); do
		x=$(depth "$n"); [ $((x + 1)) -gt $d ] && d=$((x + 1))
	done
	echo $d
}

# dependents PLUGIN -- the plugins that name it in their needs.
dependents() {
	for p in $(all_plugins); do
		case " $(field "$p" needs) " in *" $1 "*) echo "$p" ;; esac
	done
}

# older A B -- true when version A is older than B, comparing X.Y.Z by
# number; awk reads 32-dev as 32.
older() {
	awk -v a="$1" -v b="$2" 'BEGIN {
		n = split(a, x, "."); m = split(b, y, ".")
		for (i = 1; i <= (n > m ? n : m); i++) {
			if (x[i] + 0 < y[i] + 0) exit 0
			if (x[i] + 0 > y[i] + 0) exit 1
		}
		exit 1
	}'
}

# xymon_ok PLUGIN -- refuse the plugin, or one it needs, when its xymon:
# line names a newer Xymon than the server's, unless --force; say so when
# the server's cannot be read. Run on every plugin to install before any is
# touched.
CHECKED=
xymon_ok() {
	case " $CHECKED " in *" $1 "*) return 0 ;; esac
	CHECKED="$CHECKED $1"
	for n in $(field "$1" needs); do xymon_ok "$n"; done
	want=$(field "$1" xymon); [ -n "$want" ] || return 0
	have=$("$DESTDIR$XYMONHOME/bin/xymon" --version 2>/dev/null | sed -n 's/^Xymon version \([0-9][0-9.]*[^ ]*\).*/\1/p')
	if [ -z "$have" ]; then
		echo "install.sh: $1 needs Xymon $want or newer, and the version of $DESTDIR$XYMONHOME/bin/xymon could not be read: not checked" >&2
	elif older "$have" "$want"; then
		[ -n "$FORCE" ] || die "$1 needs Xymon $want or newer, and this server's is $have: --force installs it anyway"
		echo "install.sh: $1 needs Xymon $want or newer, and this server's is $have: installed anyway, as --force asks" >&2
	elif [ "$have" != "${have%%-*}" ] && ! older "$want" "${have%%-*}"; then
		echo "install.sh: $1 needs Xymon $want or newer, and this server's is $have, on the way to $want: not checked" >&2
	fi
	return 0
}

# reads_d -- say when the server's xymonserver.cfg does not read
# xymonserver.d/, where the plugins' settings go: a configuration kept from
# before 4.3.31 would ignore them all, without a word.
reads_d() {
	c=$DESTDIR$XYMONHOME/etc/xymonserver.cfg
	[ -f "$c" ] || return 0
	grep -q '^[[:space:]]*\(optional[[:space:]]\{1,\}\)\{0,1\}directory[[:space:]]\{1,\}\(.*/\)\{0,1\}xymonserver\.d/\{0,1\}[[:space:]]*$' "$c" && return 0
	echo "install.sh: $c does not read xymonserver.d/, where the plugins' settings go: add the line" >&2
	echo "  optional directory $XYMONHOME/etc/xymonserver.d" >&2
	echo "as Xymon's own xymonserver.cfg has it since 4.3.31" >&2
}

need_home() {
	[ -n "$XYMONHOME" ] || die "XYMONHOME is not set: XYMONHOME=<the Xymon server directory> ./install.sh $ACTION [PLUGIN...]"
}

# fresh DIR -- DIR, emptied: an install replaces a plugin's directory as a
# whole, so that a file a newer version no longer ships does not stay behind
# to be imported. It holds only what the plugin ships and its VERSION.
fresh() { rm -rf "$1" && mkdir -p "$1"; }

# copy PLUGIN SIDE DIR -- the side's files into DIR, executable or not.
copy() {
	exe=" $(field "$1" executable) "
	for f in $(field "$1" "$2-files"); do
		cp -f "$ROOT/plugins/$1/$f" "$3/" || exit 1
		case $exe in *" $f "*) chmod 755 "$3/$f" ;; *) chmod 644 "$3/$f" ;; esac
	done
}

# version PLUGIN DIR -- the plugin's version, in DIR/VERSION. Installed from
# a release, the commit its tag PLUGIN/vX.Y.Z names, it is that tag, which
# git checks out: the API's, which /health gives so a laptop fetches the same
# code. From any other commit, or an archive, the version in the PLUGIN file.
version() {
	v=$(git -C "$ROOT/plugins/$1" describe --exact-match --tags --match "$1/v*" 2>/dev/null) || v=$(field "$1" version)
	printf '%s\n' "$v" > "$2/VERSION" && chmod 644 "$2/VERSION"
}

# manual PLUGIN PAGE MANROOT -- the page into its section's directory.
manual() {
	[ -n "$2" ] || return 0
	mkdir -p "$3/man${2##*.}" && cp -f "$ROOT/plugins/$1/$2" "$3/man${2##*.}/" && chmod 644 "$3/man${2##*.}/$2"
}

# dist PLUGIN -- stage the plugin's directory under $DIST/plugins, as it is
# in the repository but for its tests, with this script and LICENSE beside:
# a machine unpacking it runs ./install.sh install-tools there, at the
# server's versions. Links are copied as links, as in the repository.
dist() {
	rm -rf "$DIST/plugins/$1"
	mkdir -p "$DIST/plugins"
	cp -R "$ROOT/plugins/$1" "$DIST/plugins/$1"
	rm -rf "$DIST/plugins/$1/tests"
	find "$DIST/plugins/$1" -name __pycache__ -prune -exec rm -rf {} +
	cp -f "$ROOT/install.sh" "$ROOT/LICENSE" "$DIST/"
}

# ours PLUGIN -- refuse a tasks.d/PLUGIN that is a link to something other
# than the plugin's task file: it is not ours to change.
ours() {
	if [ -L "$TASKDIR/$1" ] && [ "$(readlink "$TASKDIR/$1")" != "$XYMONHOME/ext/$1/tasks.cfg" ]; then
		die "$TASKDIR/$1 is a link to $(readlink "$TASKDIR/$1"), not $1's task: left alone"
	fi
}

# task PLUGIN -- its xymonlaunch task file, @XYMONHOME@ replaced, kept in
# the plugin's directory as ext/PLUGIN/tasks.cfg. The task is on when
# tasks.d/PLUGIN, a link to that file, is there: removing ext/PLUGIN by hand
# then takes the task with it, since xymonlaunch skips a link that points
# nowhere and stops the task at its next reload, where a copy in tasks.d
# would have it log that it cannot start the task, forever. A first install
# makes no link. A later one keeps the task file as the admin left it --
# install_server sets it aside before it replaces the directory -- and
# whether the task is on. A regular file at tasks.d/PLUGIN wins over the
# one set aside, as it is the one xymonlaunch was reading: the copy an older
# install made there, or what an editor that writes by renaming, "sed -i"
# among them, left where the link was. It is moved into the directory, and
# linked. Older installs said off with a DISABLED line in the file: a file
# with one is off, its line taken out and its link removed.
task() {
	t=$(field "$1" task); [ -n "$t" ] || return 0
	tf=$EXTROOT/$1/tasks.cfg
	link=$TASKDIR/$1
	ours "$1"
	mkdir -p "$TASKDIR"
	on=
	if [ -f "$link" ] && [ ! -L "$link" ]; then
		on=1
		rm -f "$EXTROOT/.$1.tasks.cfg"
		mv "$link" "$tf" || exit 1
		echo "keeping $link, moved to $tf"
	elif [ -f "$EXTROOT/.$1.tasks.cfg" ]; then
		[ -L "$link" ] && on=1
		mv "$EXTROOT/.$1.tasks.cfg" "$tf" || exit 1
		echo "keeping $tf"
	else
		sed -e "s|@XYMONHOME@|$(sedesc "$XYMONHOME")|g" "$ROOT/plugins/$1/$t" > "$tf" && chmod 644 "$tf"
	fi
	if grep -q '^[[:space:]]*DISABLED[[:space:]]*$' "$tf"; then
		on=
		sed -e '/^[[:space:]]*DISABLED[[:space:]]*$/d' "$tf" > "$tf.new" && mv "$tf.new" "$tf" && chmod 644 "$tf" || exit 1
		echo "$1's task was DISABLED: it is off, and ./install.sh enable-server $1 turns it on"
	fi
	rm -f "$link"
	[ -z "$on" ] || ln -s "$XYMONHOME/ext/$1/tasks.cfg" "$link" || exit 1
}

# enable PLUGIN, disable PLUGIN -- its task on or off, by its link.
enable() {
	[ -n "$(field "$1" task)" ] || die "$1 has no task to enable"
	[ -f "$EXTROOT/$1/tasks.cfg" ] || die "$1 is not installed in $EXTROOT"
	ours "$1"
	[ -L "$TASKDIR/$1" ] && { echo "$1 is on already"; return 0; }
	mkdir -p "$TASKDIR"
	ln -s "$XYMONHOME/ext/$1/tasks.cfg" "$TASKDIR/$1" || exit 1
	echo "$1 is on: xymonlaunch starts it within half a minute"
}
disable() {
	[ -n "$(field "$1" task)" ] || die "$1 has no task to disable"
	ours "$1"
	[ -L "$TASKDIR/$1" ] || { echo "$1 is off already"; return 0; }
	rm -f "$TASKDIR/$1"
	echo "$1 is off: xymonlaunch stops it within half a minute"
}

# installed_tasks -- the plugins named, or every one installed with a task.
installed_tasks() {
	for n in $LIST; do
		if [ -n "$NAMES" ] || { [ -n "$(field "$n" task)" ] && [ -d "$EXTROOT/$n" ]; }; then echo "$n"; fi
	done
}

# conf PLUGIN -- its web server snippets into $XYMONHOME/etc unless there
# already: an admin's edits are kept, as a task file is.
conf() {
	for c in $(field "$1" conf); do
		if [ -e "$ETC/$c" ]; then
			echo "keeping $ETC/$c"
		else
			cp "$ROOT/plugins/$1/$c" "$ETC/" && chmod 644 "$ETC/$c"
		fi
	done
}

# restart PLUGIN -- a process that runs the plugin's program from this
# install keeps the code it loaded: stop it, and xymonlaunch starts the new.
# Found by its command line, which names the program by its full path,
# escaped for pgrep's regular expressions, as a directory may hold a | or a
# dot. With DESTDIR the path is the staging one, which nothing runs from.
restart() {
	prog=$(field "$1" restart); [ -n "$prog" ] || return 0
	if ! command -v pgrep >/dev/null 2>&1; then
		echo "An API that runs keeps the old code until it is stopped; xymonlaunch then starts the new."
		return 0
	fi
	pat=$(printf '%s/%s' "$EXTROOT/$1" "$prog" | sed -e 's/[][\\.*^$|+?(){}]/\\&/g')
	pids=$(echo $(pgrep -f "$pat" | grep -vx "$$"))
	[ -n "$pids" ] || return 0
	if kill $pids 2>/dev/null; then
		echo "Stopped the API that ran the old code (PID $pids): xymonlaunch starts the new one."
	else
		echo "Could not stop the API that runs the old code (PID $pids): stop it with kill $pids, and xymonlaunch starts the new one." >&2
	fi
}

# offer QUESTION -- on a terminal, ask it; true on y. Without one, false.
offer() {
	[ -t 0 ] && [ -t 1 ] || return 1
	printf '%s [y/N] ' "$1"
	read -r yn
	case $yn in [yY]*) return 0 ;; esac
	return 1
}

# venv_auto PLUGIN ROOT MODULES TARGET NOTE -- the last step of installing a
# plugin that needs the Python modules MODULES (their import names), which
# downloads nothing unless asked. With no virtualenv at ROOT/venv yet: the
# newest Python 3.9 or later on this machine that has them already --
# PYTHON when given, else python3.14 down to python3.9 and python3, on PATH
# and in Homebrew's and pyenv's directories -- is made the virtualenv's,
# with --system-site-packages, so that it is only pinned beside the plugins
# and nothing is copied or fetched; with no such Python, the hint says which
# ./install.sh TARGET would use. A candidate is named by the interpreter it
# runs (sys.executable), not a shim or link found on PATH. With a virtualenv
# there, the modules it lacks are named. On a terminal the hint is an offer:
# on "y", ./install.sh TARGET -- venv-server or venv-tools -- installs the modules
# from PyPI there and then. NOTE says in the offer what the modules are for.
venv_auto() {
	plugin=$1 root=$2 modules=$3 target=$4 note=$5
	[ -n "$modules" ] || return 0
	if [ -x "$root/venv/bin/python3" ]; then
		missing=$("$root/venv/bin/python3" -c 'import importlib.util as u, sys; print(" ".join(m for m in sys.argv[1:] if u.find_spec(m) is None))' $modules)
		[ -z "$missing" ] && return 0
		if offer "The virtualenv $root/venv lacks $missing, which $plugin needs${note:+ ($note)}. Install them into it, from PyPI?"; then
			"$ROOT/install.sh" "$target" || exit 1
		else
			echo "The virtualenv $root/venv lacks $missing, which this plugin needs: ./install.sh $target installs them."
		fi
		return 0
	fi
	py= newest=
	for c in ${PYTHON_GIVEN:-python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3}; do
		for d in "" /opt/homebrew/bin /usr/local/bin /opt/homebrew/opt/python@3.*/bin "$HOME"/.pyenv/versions/*/bin; do
			case $c in
				/*) p=$c ;;
				*) if [ -n "$d" ]; then p=$d/$c; else p=$(command -v "$c" 2>/dev/null); fi ;;
			esac
			[ -n "$p" ] && [ -x "$p" ] || continue
			"$p" -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null || continue
			real=$("$p" -c 'import sys; print(sys.executable)' 2>/dev/null)
			[ -n "$real" ] && [ -x "$real" ] && p=$real
			[ -n "$newest" ] || newest=$p
			"$p" -c 'import importlib.util as u, sys; sys.exit(any(u.find_spec(m) is None for m in sys.argv[1:]))' $modules 2>/dev/null || continue
			py=$p; break 2
		done
	done
	if [ -n "$py" ]; then
		"$py" -m venv --system-site-packages "$root/venv" || exit 1
		echo "Made $root/venv from $py ($("$py" -V 2>&1)), which has the modules this plugin needs ($modules): the plugins there run with it."
	elif [ -n "$newest" ] && offer "$plugin needs $modules, which no Python here has${note:+ ($note)}. Make a virtualenv at $root/venv with $newest, and install them from PyPI?"; then
		PYTHON=$newest "$ROOT/install.sh" "$target" || exit 1
	else
		echo "No virtualenv at $root/venv, and no Python with the modules this plugin needs ($modules): ./install.sh $target${newest:+ PYTHON=$newest} makes one and installs them; without it, the python3 on PATH must have them."
	fi
}

# venv ROOT -- a virtualenv at ROOT/venv, beside the plugins installed in
# ROOT, with the modules of each, from the requirements.txt installed with
# it: what every launcher runs with when XYMONAPI_PYTHON names no other. Run
# again, it adds the modules of a plugin installed since.
venv() {
	[ -d "$1" ] || die "nothing is installed in $1 yet"
	[ -x "$1/venv/bin/python3" ] || "$PYTHON" -m venv "$1/venv" || exit 1
	for r in "$1"/*/requirements.txt; do
		[ -e "$r" ] || continue
		echo "installing the modules of $r"
		"$1/venv/bin/python3" -m pip install -q -r "$r" || exit 1
	done
	echo "The plugins in $1 run with $1/venv/bin/python3 ($("$1/venv/bin/python3" -V))."
}

DONE=
install_server() {
	case " $DONE " in *" $1 "*) return 0 ;; esac
	for n in $(field "$1" needs); do install_server "$n"; done
	[ -n "$(field "$1" server-files)" ] || die "$1 has nothing to install on the server"
	ext=$EXTROOT/$1
	# Refused before anything is replaced, not halfway through.
	[ -z "$(field "$1" task)" ] || ours "$1"
	# The task file an admin may have enabled outlives the directory.
	if [ -f "$ext/tasks.cfg" ]; then mv "$ext/tasks.cfg" "$EXTROOT/.$1.tasks.cfg" || exit 1; fi
	fresh "$ext" || exit 1
	copy "$1" server "$ext"
	version "$1" "$ext"
	dist "$1"
	manual "$1" "$(field "$1" server-manual)" "$DESTDIR$MANDIR"
	task "$1"
	conf "$1"
	say "$1" installed
	restart "$1"
	venv_auto "$1" "$EXTROOT" "$(field "$1" server-modules)" venv-server ""
	DONE="$DONE $1"
}

install_tools() {
	case " $DONE " in *" $1 "*) return 0 ;; esac
	for n in $(field "$1" needs); do install_tools "$n"; done
	[ -n "$(field "$1" tools-files)" ] || die "$1 has nothing to install on your own machine"
	dir=$TOOLSROOT/$1
	fresh "$dir" || exit 1
	mkdir -p "$BIN" "$TOOLSMAN1"
	copy "$1" tools "$dir"
	version "$1" "$dir"
	set -- "$1" $(field "$1" command)
	if [ $# -eq 3 ]; then
		# The command runs the script from where it is installed: PREFIX as
		# given, without DESTDIR, quoted.
		printf '#!/bin/sh\nexec "%s/libexec/xymon-plugins/%s/%s" "$@"\n' "$PREFIX" "$1" "$3" > "$BIN/$2"
		chmod 755 "$BIN/$2"
	fi
	manual "$1" "$(field "$1" tools-manual)" "$DESTDIR$PREFIX/share/man"
	venv_auto "$1" "$TOOLSROOT" "$(field "$1" tools-modules)" venv-tools "$(field "$1" venv-note)"
	DONE="$DONE $1"
}

# needed PLUGIN DIR -- refuse to remove the plugin while one installed in DIR
# needs it beside it: removing it would leave that one broken.
needed() {
	for d in $(dependents "$1"); do
		[ -e "$2/$d" ] && die "$1 is needed by $d, installed in $2: uninstall $d first"
	done
	return 0
}

uninstall_server() {
	needed "$1" "$EXTROOT"
	needed "$1" "$DIST/plugins"
	rm -rf "$EXTROOT/$1" "$DIST/plugins/$1"
	m=$(field "$1" server-manual)
	[ -n "$m" ] && rm -f "$DESTDIR$MANDIR/man${m##*.}/$m"
	[ -n "$(field "$1" task)" ] && rm -f "$TASKDIR/$1"
	say "$1" uninstalled
}

uninstall_tools() {
	needed "$1" "$TOOLSROOT"
	rm -rf "$TOOLSROOT/$1"
	set -- "$1" $(field "$1" command)
	[ $# -eq 3 ] && rm -f "$BIN/$2"
	m=$(field "$1" tools-manual)
	[ -n "$m" ] && rm -f "$TOOLSMAN1/$m"
	say "$1" uninstalled-tools
}

case $ACTION in
	install-client|uninstall-client|venv-client)
		die "$ACTION is now ${ACTION%-client}-tools: the plugins' commands, on your own machine. A client, here, is Xymon's, on a monitored host, and nothing installs one yet." ;;
esac

# The plugins named, each checked, or every plugin; for an uninstall, the
# deepest first, so that none is removed while one installed needs it.
for n in $NAMES; do known "$n"; done
if [ -n "$NAMES" ]; then LIST=$NAMES; else LIST=$(all_plugins); fi
deepest_first() {
	for n in $LIST; do echo "$(depth "$n") $n"; done | sort -rn | cut -d' ' -f2
}

case $ACTION in
	install|install-server)
		need_home
		for n in $LIST; do xymon_ok "$n"; done
		reads_d
		for n in $LIST; do install_server "$n"; done ;;
	install-tools)
		for n in $LIST; do install_tools "$n"; done ;;
	enable|enable-server)
		need_home
		for n in $(installed_tasks); do enable "$n"; done ;;
	disable|disable-server)
		need_home
		for n in $(installed_tasks); do disable "$n"; done ;;
	uninstall|uninstall-server)
		need_home
		for n in $(deepest_first); do uninstall_server "$n"; done
		[ -n "$NAMES" ] || rm -rf "$EXTROOT/venv" ;;
	uninstall-tools)
		for n in $(deepest_first); do uninstall_tools "$n"; done
		if [ -z "$NAMES" ]; then
			rm -rf "$TOOLSROOT/venv"
			rmdir "$TOOLSROOT" 2>/dev/null || true
		fi ;;
	venv|venv-server)
		need_home
		venv "$EXTROOT" ;;
	venv-tools)
		venv "$TOOLSROOT" ;;
	*) usage ;;
esac
