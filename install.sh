#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install, update and remove the plugins, on the Xymon server or on another
# machine, with nothing but a POSIX shell and the usual tools: no make.
#
#   ./install.sh                     on a terminal: asks what to do, and does it
#   ./install.sh install [PLUGIN...]
#   ./install.sh remove [PLUGIN...]
#   ./install.sh venv                the virtualenv beside the plugins
#
# Which side an action serves is the role this machine plays, told by
# XYMONHOME: set -- by xymoncmd, the Xymon user's environment, or on the
# command line -- the Xymon server's part, the plugins' tasks and the API
# under $XYMONHOME/ext; unset, your own machine's, the plugins' commands
# under PREFIX (~/.local). On a server machine, XYMONHOME= ./install.sh
# install installs your own commands. Nothing installs on a monitored host,
# Xymon's client, yet.
#
# With no action at all, on a terminal, the script asks: install or remove,
# which role this machine plays, the detected one by default, and which
# plugins, Enter taking each default; it then runs the action those answers
# spell, saying which, so the words are there to copy for next time.
# Without a terminal, no action means the usage.
#
# With no PLUGIN, every plugin of that side. A plugin that needs another
# installs it first, and a removal is refused while one installed needs
# the plugin removed. Running an install again updates: each plugin's
# directory is replaced as a whole, and the admin's task files, web server
# snippets and data are kept. Settings come from the environment, or as
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
	echo "usage: ./install.sh install|remove|venv [PLUGIN...] [NAME=value...]   the Xymon server's part with XYMONHOME set, else your own machine's" >&2
	echo "       ./install.sh                                                on a terminal: asks what to do" >&2
	exit 2
}

# The first word that is not a NAME=value setting is the action, the
# others the plugins. No action on a terminal is the dialogue, which runs
# once the helpers below are defined; no action elsewhere is the usage.
ACTION=
NAMES=
for a in "$@"; do
	case $a in
		*=*) export "$a" ;;
		*) if [ -z "$ACTION" ]; then ACTION=$a; else NAMES="$NAMES $a"; fi ;;
	esac
done
DIALOGUE=
if [ -z "$ACTION" ]; then
	[ -t 0 ] && [ -t 1 ] || usage
	DIALOGUE=1
fi

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
# none. Removing every plugin goes from the deepest up.
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
# a machine unpacking it runs ./install.sh install there, as itself, at the
# server's versions. Links are copied as links, as in the repository.
dist() {
	rm -rf "$DIST/plugins/$1"
	mkdir -p "$DIST/plugins"
	cp -R "$ROOT/plugins/$1" "$DIST/plugins/$1"
	rm -rf "$DIST/plugins/$1/tests"
	find "$DIST/plugins/$1" -name __pycache__ -prune -exec rm -rf {} +
	cp -f "$ROOT/install.sh" "$ROOT/LICENSE" "$DIST/"
}

# task PLUGIN -- its xymonlaunch task file as tasks.d/PLUGIN, @XYMONHOME@
# replaced, unless one is there already: the one an admin enabled is not put
# back to DISABLED by the next install.
task() {
	t=$(field "$1" task); [ -n "$t" ] || return 0
	mkdir -p "$TASKDIR"
	if [ -e "$TASKDIR/$1" ]; then
		echo "keeping $TASKDIR/$1"
	else
		sed -e "s|@XYMONHOME@|$(sedesc "$XYMONHOME")|g" "$ROOT/plugins/$1/$t" > "$TASKDIR/$1" && chmod 644 "$TASKDIR/$1"
	fi
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

# ask QUESTION DEFAULT -- on a terminal, the answer to QUESTION, DEFAULT
# when Enter alone is typed.
ask() {
	printf '%s [%s] ' "$1" "$2" >&2
	read -r answer
	[ -n "$answer" ] && echo "$answer" || echo "$2"
}

# dialogue -- the questions ./install.sh asks when given no word on a
# terminal, then the action they spell, run as if its words had been typed.
# The role defaults to the one XYMONHOME detects: set, the Xymon server;
# unset, your own machine. The plugins offered are those of that role and,
# for a removal, those installed; a plugin unticked takes with it the ones
# that need it, and a plugin removed takes its installed dependents, each
# named, since that is what the actions themselves insist on.
dialogue() {
	echo "The Xymon plugins. Enter takes the answer in brackets."
	verb=$(ask "Install or remove?" install)
	case $verb in
		i*) verb=install ;;
		r*) verb=remove ;;
		*) die "neither install nor remove: '$verb'" ;;
	esac
	if [ -n "$XYMONHOME" ]; then role=1; else role=2; fi
	echo "Which role does this machine play?"
	echo "  1. the Xymon server: the plugins' tasks and the API, under ${XYMONHOME:-XYMONHOME}/ext"
	echo "  2. your own machine: the plugins' commands, under $PREFIX"
	role=$(ask "Role" "$role")
	case $role in
		1*) side=server; files=server-files; root=$EXTROOT ;;
		2*) side=tools; files=tools-files; root=$TOOLSROOT ;;
		*) die "neither 1 nor 2: '$role'" ;;
	esac
	if [ "$side" = server ] && [ -z "$XYMONHOME" ]; then
		XYMONHOME=$(ask "XYMONHOME, the Xymon server directory" /usr/lib/xymon/server)
		root=$DESTDIR$XYMONHOME/ext
	fi
	# The side reaches the action as XYMONHOME: set for the server's, empty
	# for your own machine's, whatever the environment held.
	[ "$side" = server ] || XYMONHOME=
	export XYMONHOME
	offered=
	for p in $(for p in $(all_plugins); do echo "$(depth "$p") $p"; done | sort -n | cut -d' ' -f2); do
		[ -n "$(field "$p" $files)" ] || continue
		[ "$verb" = install ] || [ -e "$root/$p" ] || continue
		offered="$offered $p"
	done
	[ -n "$offered" ] || die "nothing to $verb for that role: no plugin installed in $root"
	echo "Plugins, all of them unless you name some:"
	for p in $offered; do
		printf '  %-16s %s\n' "$p" "$(field "$p" summary)"
	done
	chosen=$(ask "Plugins" "$(echo $offered)")
	for n in $chosen; do
		known "$n"
		case " $offered " in *" $n "*) ;; *) die "$n is not among the plugins to $verb here" ;; esac
	done
	if [ "$verb" = install ]; then
		for n in $chosen; do
			for d in $(field "$n" needs); do
				case " $chosen " in *" $d "*) ;; *) chosen="$chosen $d"; echo "With $d, which $n needs." ;; esac
			done
		done
	else
		for n in $chosen; do
			for d in $(dependents "$n"); do
				[ -e "$root/$d" ] || continue
				case " $chosen " in *" $d "*) ;; *) chosen="$chosen $d"; echo "With $d, installed here, which needs $n." ;; esac
			done
		done
	fi
	[ "$(echo $chosen)" = "$(echo $offered)" ] && [ "$verb" = install ] && chosen=
	echo "Running: ${XYMONHOME:+XYMONHOME=$XYMONHOME }./install.sh $verb $(echo $chosen)"
	echo
	exec "$ROOT/install.sh" "$verb" $chosen
}

# venv_auto PLUGIN ROOT MODULES NOTE -- the last step of installing a
# plugin that needs the Python modules MODULES (their import names), which
# downloads nothing unless asked. With no virtualenv at ROOT/venv yet: the
# newest Python 3.9 or later on this machine that has them already --
# PYTHON when given, else python3.14 down to python3.9 and python3, on PATH
# and in Homebrew's and pyenv's directories -- is made the virtualenv's,
# with --system-site-packages, so that it is only pinned beside the plugins
# and nothing is copied or fetched; with no such Python, the hint says which
# ./install.sh venv would use. A candidate is named by the interpreter it
# runs (sys.executable), not a shim or link found on PATH. With a virtualenv
# there, the modules it lacks are named. On a terminal the hint is an offer:
# on "y", ./install.sh venv installs the modules from PyPI there and then.
# NOTE says in the offer what the modules are for.
venv_auto() {
	plugin=$1 root=$2 modules=$3 note=$4
	[ -n "$modules" ] || return 0
	# The hint, as typed on this side: XYMONHOME names the server's.
	target="${XYMONHOME:+XYMONHOME=... }./install.sh venv"
	if [ -x "$root/venv/bin/python3" ]; then
		missing=$("$root/venv/bin/python3" -c 'import importlib.util as u, sys; print(" ".join(m for m in sys.argv[1:] if u.find_spec(m) is None))' $modules)
		[ -z "$missing" ] && return 0
		if offer "The virtualenv $root/venv lacks $missing, which $plugin needs${note:+ ($note)}. Install them into it, from PyPI?"; then
			"$ROOT/install.sh" venv || exit 1
		else
			echo "The virtualenv $root/venv lacks $missing, which this plugin needs: $target installs them."
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
		PYTHON=$newest "$ROOT/install.sh" venv || exit 1
	else
		echo "No virtualenv at $root/venv, and no Python with the modules this plugin needs ($modules): $target${newest:+ PYTHON=$newest} makes one and installs them; without it, the python3 on PATH must have them."
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
	fresh "$ext" || exit 1
	copy "$1" server "$ext"
	version "$1" "$ext"
	dist "$1"
	manual "$1" "$(field "$1" server-manual)" "$DESTDIR$MANDIR"
	task "$1"
	conf "$1"
	say "$1" installed
	restart "$1"
	venv_auto "$1" "$EXTROOT" "$(field "$1" server-modules)" ""
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
	venv_auto "$1" "$TOOLSROOT" "$(field "$1" tools-modules)" "$(field "$1" venv-note)"
	DONE="$DONE $1"
}

# needed PLUGIN DIR -- refuse to remove the plugin while one installed in DIR
# needs it beside it: removing it would leave that one broken.
needed() {
	for d in $(dependents "$1"); do
		[ -e "$2/$d" ] && die "$1 is needed by $d, installed in $2: remove $d first"
	done
	return 0
}

remove_server() {
	needed "$1" "$EXTROOT"
	needed "$1" "$DIST/plugins"
	rm -rf "$EXTROOT/$1" "$DIST/plugins/$1"
	m=$(field "$1" server-manual)
	[ -n "$m" ] && rm -f "$DESTDIR$MANDIR/man${m##*.}/$m"
	[ -n "$(field "$1" task)" ] && rm -f "$TASKDIR/$1"
	say "$1" removed
}

remove_tools() {
	needed "$1" "$TOOLSROOT"
	rm -rf "$TOOLSROOT/$1"
	set -- "$1" $(field "$1" command)
	[ $# -eq 3 ] && rm -f "$BIN/$2"
	m=$(field "$1" tools-manual)
	[ -n "$m" ] && rm -f "$TOOLSMAN1/$m"
	say "$1" removed-tools
}

[ -z "$DIALOGUE" ] || dialogue

# The plugins named, each checked, or every plugin; for a removal, the
# deepest first, so that none is removed while one installed needs it.
for n in $NAMES; do known "$n"; done
if [ -n "$NAMES" ]; then LIST=$NAMES; else LIST=$(all_plugins); fi
deepest_first() {
	for n in $LIST; do echo "$(depth "$n") $n"; done | sort -rn | cut -d' ' -f2
}

# The side: the Xymon server's with XYMONHOME set, else your own machine's.
if [ -n "$XYMONHOME" ]; then SIDE=server; else SIDE=tools; fi
case $ACTION-$SIDE in
	install-server)
		for n in $LIST; do install_server "$n"; done ;;
	install-tools)
		for n in $LIST; do install_tools "$n"; done ;;
	remove-server)
		for n in $(deepest_first); do remove_server "$n"; done
		[ -n "$NAMES" ] || rm -rf "$EXTROOT/venv" ;;
	remove-tools)
		for n in $(deepest_first); do remove_tools "$n"; done
		if [ -z "$NAMES" ]; then
			rm -rf "$TOOLSROOT/venv"
			rmdir "$TOOLSROOT" 2>/dev/null || true
		fi ;;
	venv-server)
		venv "$EXTROOT" ;;
	venv-tools)
		venv "$TOOLSROOT" ;;
	*) usage ;;
esac
