# xymon-plugins specification

The rules of the plugin model: what a plugin is, where its files go, how it
is installed, updated and removed, and what the administrator can count on.

Every numbered rule is enforced by a test: each test that checks a rule cites
it as `[S<n>]` in an assertion's message, and `tests/compat/spec-rules.sh`
fails when a rule is cited by no test, or a test cites a rule this file does
not number. That test prints which tests check each rule. A rule is numbered
in the pull request that brings its test; until then it is under Planned.
Numbers are not reused. A rule changes through a pull request to this file.

How a change is made and reviewed, and how versions move, is in
`CONTRIBUTING.md`; how to install and use the plugins, in `README.md` and
`plugins/README.md`. This file holds the guarantees those pages describe.

## Goal

An administrator adds a plugin to Xymon, switches it on, updates it and
takes it away again, the same way for every plugin, and never ends up with a
Xymon that runs, reads or serves something of a plugin that is gone.

## Principles

Where the rules lead; the rules say what holds today, Planned what is still
to come.

- **A plugin lives in its directory.** Everything a plugin installs is under
  its directory: `$XYMONHOME/ext/NAME/` on the Xymon server, the client's
  `ext/NAME/` on a monitored host, `$PREFIX/libexec/xymon-plugins/NAME/` on
  your own machine. What another program must find elsewhere -- a task, a
  setting, a manual page, a web server snippet -- is a link into that
  directory, or a file that program reads only when it exists. Every
  other place a plugin may write is listed, once, in S28: a place not
  listed there is not a plugin's to write.
- **Removing the directory removes the plugin.** Deleting an `ext/NAME`
  directory by hand is a valid way to take away the part installed there;
  the plugin is gone once every directory holding one of its parts has
  been removed.
  Then no task of it runs, no setting of it
  applies, nothing of it is served, and no program reports an error. What is
  left is at most a link that points nowhere, which every reader skips, and
  which the next removal takes away -- or a SELinux module, which grants
  nothing while its booleans are off (S23).
- **Installing does not enable.** An install puts the files in place and
  changes nothing that runs; switching a plugin on is a step of its own, and
  so is switching it off.
- **What the administrator chose survives an update.** Updating
  replaces a plugin's code and keeps whether it is on, and its settings.
- **What the administrator wants to keep lives outside.** Data that should
  outlive the plugin -- the API's tokens, a search index -- is kept outside
  its directory, and does nothing once the plugin is gone.
- **What a plugin makes while it runs lies where Xymon keeps its own.** A socket
  is in Xymon's runtime directory, its own directory there, made when it
  starts and taken away when it stops; a log, in Xymon's log directory.
- **One command, nothing particular to a plugin.** The command reads each
  plugin's `PLUGIN` file and holds no other plugin's name -- it is one of
  them itself; a new plugin is a directory and its `PLUGIN` file.
- **Every rule is enforced by a test**, so a change that breaks one fails at
  once.

## Rules

### What a plugin is

**S1. A plugin is a directory with a `PLUGIN` file.**
`plugins/NAME/` holds the `PLUGIN` file, a README, a manual page per side,
tests and the code. `xymon-plugin` installs every plugin from its `PLUGIN`
file, and names none but its own: it is one of them, `plugins/xymon-plugin/`,
which `./xymon-plugin` at the repository's top links to and which also runs
as itself, its tree's top two levels up, installed as any other; a plugin
no code knows is installed, reported and removed alike.

**S2. A plugin carries its version.**
The `version:` line, `X.Y.Z`, moves as `CONTRIBUTING.md` (Versions) says. The
install writes it beside the installed files, in `VERSION`, from a checkout
or a release's archive alike: whether the code is exactly a release's is
said by `status` and `verify` (S15, S30), and an archive's attestation. The
installer's own version, which `--version` gives, is its `PLUGIN` file's.

**S3. A plugin names the plugins it needs, part by part.**
Its `server-needs:`, `client-needs:` and `tools-needs:` lines name them
for that part: the same part of each, or another with `NAME:part`. The
install of a part installs what it needs with it; a need the install
cannot hold -- a tools part for a server part, as a server install
installs no tools -- and a part that is none are refused before anything
changes. The removal of a part is refused while an installed plugin's
same part needs it, naming that plugin; for a client part, every plugin
named is checked before any is removed.

**S14. A plugin names the Xymon it needs.**
A `xymon:` line in `PLUGIN`, `X.Y.Z`, gives the lowest Xymon version the
plugin's server side works with. `install --server` compares it with what
`$XYMONHOME/bin/xymon --version` gives, for the plugin and each it needs,
before it installs any:

- older: refused, naming both versions, unless `--force` is given, which
  installs it and says so. A distribution may carry a feature back to an
  older number, and the administrator may know it does;
- not known, because the version cannot be read: installed, with a warning
  that it could not be checked;
- a development version, `4.3.32-dev`, comes after `4.3.31` and before
  `4.3.32`: a plugin that needs `4.3.32` installs on it with a warning, as
  it may lack what came before that release.

A plugin that needs a newer Xymon for one feature alone says so in its README
instead. Whatever the version, `install --server` says so when the server's
`xymonserver.cfg` does not read `xymonserver.d/`, where the plugins'
settings go: a configuration kept from before 4.3.31 ignores them.

**S4. A plugin has its sides.**
The Xymon server (`server-*` lines: files under `$XYMONHOME/ext/NAME/`, a
xymonlaunch task, a section 8 manual page), a standalone Xymon client
(`client-*` lines: files under the client tree's `ext/NAME/`, a section 8
manual page; S35) and your own machine (`tools-*` lines: files under
`$PREFIX/libexec/xymon-plugins/NAME/`, commands in `$PREFIX/bin`, a
section 1 manual page). A plugin has one side, two or all three. The
server and client sides need `XYMONHOME`, and without it install nothing
and say so. A command is written in `$PREFIX/bin` where its name is free
or holds, byte for byte, the command an install of that plugin wrote:
anything else there -- a command of the person's, a link, a directory --
is left as it is and said, with the path that runs the plugin's command,
the install going on.

**S18. A part acts only on its own kind of tree.**
The tree `XYMONHOME` names is read for Xymon's marks, a whole pair counting
before any single mark: a server's, `etc/xymonserver.cfg` and `bin/xymond`,
which wins when a client's files are there too; else a client's,
`etc/xymonclient.cfg` and `bin/xymonclient.sh`. `--server` takes a server's
tree, `--client` a client's, whose `ext/` must be a directory -- or a
server's, standing for its own client tree (S36). Any other
tree -- of the other kind, with one mark of a pair, or with no marks -- is
refused before anything changes, naming the marks found or missing and,
for a tree of the other kind, the part it takes. Under `DESTDIR`, a staging
target, the marks are not read. Without `XYMONHOME`, the Xymon trees found
on the machine are named, and none is chosen.

### Installing, updating, removing

**S5. Installing enables nothing.**
A plugin's task is installed off, with no link (S13); the install says how
to turn it on.

**S6. A plugin's task lives in its directory.**
The `server-task:` line of its `PLUGIN` names the server part's file,
`client-task:` the client part's; installed, it is `ext/NAME/tasks.cfg` in
that part's tree. A task is named after its part: a server part's file
has the one section `[NAME-server]`, and on the server
`etc/tasks.d/NAME-server.cfg`, when there, is a link to it; a client part's
has `[NAME-client]`, linked as `NAME-client.cfg`; the installer's own
server task alone keeps `[xymon-plugin]` and `xymon-plugin.cfg`. Two tasks
of one name, xymonlaunch makes one of them, unsaid: `enable` refuses a task
whose name xymonlaunch reads already -- through Xymon's `xymoncfg`, its
`include` and `directory` lines followed, or, without it and under
`DESTDIR`, the launcher's file and every file of its task directory --, and
a second link to its own task file, naming the `mv` that renames the
first. A test of the repository
holds each shipped task file to its one section of that name, with no
`include` or `directory` line, and refuses a plugin named with a
`-server` or `-client` ending, so that a part's names are never another
plugin's; the file installed, the administrator's, is
not refused for its section. Under `DESTDIR` the link names the installed
file. The link ends in `.cfg` because a packaged Xymon may read only the
files of `tasks.d/` that do, where Xymon's own `tasks.cfg` reads them all.
A regular file at the link's name -- a copy an older install made, or the
file an editor left in place of the link -- is the one xymonlaunch reads:
it is moved into the plugin's directory as it was, and linked unless it
was `DISABLED`. A link at that name to something else is left as it is,
and the install, before it installs anything, `enable` and `disable`
refused. A client part's task is the same in its client's tree, with
`etc/clientlaunch.d/` and the client's `clientlaunch.cfg`, which its
xymonlaunch reads, in place of `etc/tasks.d/` and `tasks.cfg`, here and in
S7, S9 and S13; `enable --client` and `disable --client` turn it on and
off. In a client part's task file, `@LOGDIR@` is its log directory,
written at install as `$XYMONCLIENTLOGS` on a standalone client and
`$XYMONSERVERLOGS` in a server's own client tree (S36), which xymonlaunch
expands.

**S7. An update replaces the code and keeps the choices.**
`update` replaces the plugin's directory as a whole, so a file a
newer version no longer ships is gone; it keeps the task file as the
administrator left it, whether it is on, and the web server snippets as the
administrator edited them. Each of those is met with this version's and
with the version it started from, kept in `.shipped/` beside them:
unedited, it takes this version's; edited, and this version's unchanged,
or holding this version's change already, it stays, nothing said. Both changed, without a conflict, on a terminal both changes are
shown and `Apply both? [y/N]` asked: y merges them, the file before kept
as `NAME.old`. On N, off a terminal -- nothing is merged unattended --,
under `DESTDIR`, on a conflict, or without `diff3` or a version to start
from, the file stays as it is and this version's is written beside it as
`NAME.new`, said with the `diff` to run. `verify` says a `.new` or `.old`
left (S30). A task file or snippet this version no longer ships goes,
nothing said; edited -- neither as `.shipped/` keeps it nor, for a
snippet, as a version shipped it (S16) --, it is kept as `NAME.old`,
where no include line reaches it, and said, a task's link removed all the
same (S20). Such a snippet dropped while this version ships another for
the same web server, the same `-apache`, `-nginx` or `-lighttpd` before
`.conf`, would go live without the edits: the update is refused before
anything changes, for every plugin named and every part it needs, naming
both, until the edited one is moved out of the plugin's directory, its
edits to carry into the new one before the web server reloads.
A `NAME.old` stays through the updates after, until the administrator
removes it -- a file at any depth of the plugin's directory, hidden or
not, a link as a link, a directory so named whole; one there when the
update writes another becomes `NAME.N.old`, the first `N` free, so that
neither is lost.
What an install or an update sets aside meanwhile -- the task file, the
snippets, `.shipped/`, each `NAME.old` -- goes in one directory in
`ext/`, `.xymon-plugin.NAME`, made by `mkdir`, so that nothing already
there is written over or through, and marked by a file
`.xymon-plugin-set-aside` naming the plugin and the date it was made;
once the plugin is in place, what is left there goes back into its
directory -- a `NAME.old` as a `.old` of its own, a file this version no
longer ships as one unless as `.shipped/` has it, said, as edited or as
one that could not be told unedited, a link said and removed, what it
names left -- and the directory goes, never while it holds a file of the
administrator's. One cut short, by a failure or a signal, leaves it,
saying what it holds, and the install cut short (S20) that the next
install or update resumes with it, saying to reload the web server:
from the plugin's directory it sets aside only what that one lacks, a
file there in both and differing -- changed since -- kept as a `.old`,
said. Where
`.xymon-plugin.NAME` is there and cannot be resumed with -- a link, not
a directory, not marked for the plugin, another user's, or beside a
complete install or none -- `install` and `update` are refused before
anything changes, saying why and what to do: beside a complete install
or none, marked, it is stale, the administrator's to compare and
remove, or, the plugin's directory gone, to take back from, said with
its date, as `remove` and `verify` name it too, `verify` as untidy
(S30); one not marked is said to be no set-aside directory. The
refusal of a replaced snippet the administrator edited (above) holds
for any run resuming, and names where the edited one lies. A task file
in place of the link that this one replaces, the task file set aside
edited too, has that one kept as a `.old`, said.
A long-running plugin takes up the update by itself: the API watches its
`MANIFEST` and xymonapi-rag's, whose code its `/search` loads, the update
command's last step (S29), and once one is written anew stops
as on SIGTERM, ending with 0, for xymonlaunch to start the new code if its
task is on; while one is gone, as during an update, and in a checkout,
which has none, it goes on; started while one was gone, it stops once it
is there.

**S8. Removing takes away the plugin and its links.**
The removal takes away the plugin's directory, its task link and its manual
pages, and is refused while another installed plugin needs it (S3). The
removal of the last plugin of a part takes away what the plugins shared
there: the virtualenv, and on the server the stage `/plugins` serves.

**S9. Removing the directory by hand removes the task.**
Once `ext/NAME` is deleted, xymonlaunch no longer has the plugin's task, and
says nothing of the link left pointing nowhere; the next removal of that
plugin, or `clean` (S31), takes that link away, and `verify` says it is
left (S30).

**S10. The administrator's data outlives the plugin.**
The removal keeps the API's tokens file, and says what it kept.

**S16. A plugin's web server snippet lives in its directory.**
A snippet the `conf:` line of `PLUGIN` names is installed in `ext/NAME/`,
`@XYMONHOME@` in it filled in as in the task file, and the web server is
told to include it in a way that skips it once it is gone: `IncludeOptional`
on Apache, a wildcard `include` on nginx and lighttpd. Removing the plugin,
or deleting `ext/NAME`, removes it, and the web server still starts. A
snippet an install finds as an older
version shipped it, by the cksum its `PLUGIN` file's `conf-stock:` lines
give -- its `$XYMONHOME` put back as `@XYMONHOME@`, so that one installed
under any tree is recognised -- was never edited, and takes this version's;
so does one byte for byte as an earlier install wrote it, which the install
keeps beside it in `ext/NAME/.shipped/`, where no include reaches it -- a
snippet naming a runtime directory moved since is not the administrator's.
One that differs from both is the administrator's, kept, and the install
says it differs. A web server goes on with the snippets it read until it
reloads: when an install adds, replaces or drops a snippet, or an uninstall
takes them away, it says to reload the web server, and reloads none itself;
under `DESTDIR` there is none to reload. A snippet is written as a new file,
never through a link, symbolic or hard; one kept as edited that does not
name Xymon's runtime directory is said to.

**S13. A plugin is on when its link is there, and read.**
A plugin's task is on when its link in `etc/tasks.d/` (S6) names its task
file and the server's `tasks.cfg` reads `tasks.d/`, and off when the link is
absent: xymonlaunch has the task exactly then. `enable` makes the link,
`disable` removes it, and each says so when there is nothing to do.
An install or update keeps the link and the file it names in place
throughout -- the file replaced by a rename, never removed first; one that
is itself a link, not the install's, is set aside and written anew -- so
that xymonlaunch, reading `tasks.d/` meanwhile, never drops the task.
A command that must change what `tasks.d/` holds where nothing can be
made there: an install or update is refused before anything is
replaced; `enable` and `disable` fail, the task as it was; `remove`
fails after the plugin's directory is gone, the link left for `clean`;
each says which.
Having made the link, `enable` changes the time of the `tasks.cfg` that
reads `tasks.d/`, not its content, so that xymonlaunch reads it again: it
watches a directory only if it was there when it read that file, and a
`tasks.d/` made since -- by this `enable`, an install, or by hand -- would
not be read until then; one that cannot be written is said, with the
restart that does it.
Before it makes the link, `enable` looks for the line by which the
server's `tasks.cfg` reads `tasks.d/`, a `directory` line naming it, as
Xymon's own has it. Where there is none, it refuses, makes no link, and
says the line to add; `--force` makes the link all the same, where the
server reads `tasks.d/` another way, and says the task may not start.
With no `tasks.cfg`, and under `DESTDIR`, nothing is looked at. The task
file carries no `DISABLED`: one an
older install wrote with that line is off, and the line is taken out, and
the install says how to turn it on.

**S19. `/plugins` serves only what a plugin declares.**
What a server stages for `/plugins`, in `ext/xymon-plugins-dist`, is for
each plugin its `PLUGIN` file, its `README.md`, and the files, manual
pages, task and web server snippets its `PLUGIN` file names, with
`xymon-plugin`, its own `PLUGIN` file beside it as `xymon-plugin.PLUGIN`, and `LICENSE`: a file left
beside them in the checkout is not
served. Each install prunes what is staged to the same, and to the
plugins installed on the server, before staging, so that what an older
install staged, or a plugin since renamed or removed left, is not served
either; a link in the stage is removed, never written through, and a
removal that fails stops the install. A name with a `/`, `.` or `..`, in
a plugin's files or in `needs:`, or a plugin file that is a link, stops
the install before anything is copied.

**S20. An installed plugin keeps its `PLUGIN` file, and is managed by it.**
An install copies the plugin's `PLUGIN` file into its installed directory,
beside `VERSION`, and keeps its manual page there too, linked from
`MANDIR` where the page's name is free or that link already: anything else
there -- a page of the administrator's, another's link, a directory -- is
left as it is and said, the install going on. A plugin has one page for
its Xymon parts, `NAME.8`, which its server and client parts both name,
and one in section 1 for each of its tools' commands. On a server holding
both, the server part and its client part in the server's own client tree
(S36), the link is the one the first install made, the other's install
leaving it, said nothing of; the part removed first points it at the
other's copy, the last takes it. Uninstalling, enabling,
disabling, reporting `status` and checking what needs a plugin, and in
what order to remove several, read that copy, not the checkout's, so that
a checkout of another version, or one the plugin is gone from, still
removes what was installed: its directory, its command, its manual page,
its task link or the task file in the link's place -- that directory gone
(S9), only the link into it, a file at its name left and said, and no
SELinux module (S23). An action given no names covers the plugins
installed with a copy that the checkout no longer has -- but `update`,
which takes the code from the checkout, passes over each, saying so, before
anything changes: a release's archive holds its own plugin alone. An update reads the
copy before replacing it, and removes the command, manual page and task
link the installed version put in place and the new one does not. A plugin
installed before the copy existed is managed by the checkout's `PLUGIN`
file, as before, until it is installed again. The copy lies in a directory
the Xymon user can write, so it decides nothing alone: a manual page is
removed only if it is the link into the plugin's directory, a command only
if it is, byte for byte, the one an install of that plugin wrote, and a
name only if it is a plain file name.
In `ext/`, of the server and of a client (S35), `install`, `update` and
`remove` replace or take only a directory an install left: one with a
plain plugin name, not a link, with `VERSION` and its `PLUGIN` copy,
naming the plugin and that part, both plain files -- or, on the server,
from before the copy, a plain `VERSION` and no `PLUGIN`, of a plugin the
checkout has. `MANIFEST` is no part of it, deciding nothing alone (S29):
an update cut short after `VERSION` is put right by the next. An install
or update writes, before anything in `ext/NAME` changes, a file there,
`.xymon-plugin-in-progress`, naming the plugin and its process, made new
-- with noclobber, never through a link -- in the one step that finds
none there, and removes it, its own, once `VERSION` is written: a
directory, not a link, holding it as a plain file naming the plugin, is
an install cut short, whatever else it holds, and nothing else is taken
for one. It is resumed by `install` and `update`, the files it set aside
put back (S7) -- refused, as is `remove`, while the process it names
runs an xymon-plugin, as `ps` says, a second run on the same plugin,
which `remove --all` and `update` with none named pass over, saying it
runs -- and refused by `remove`, naming the `update` that resumes it, unless it
is a first install's, as the file in progress says, with nothing set
aside, nothing of the administrator's, which `remove` takes.
It counts as present for a need, for `remove`'s virtualenv and for
`clean`, which leave what is its, and `status` says it is cut short. An
update of an install from before the `PLUGIN` copy replaces the manual
page it copied into `MANDIR` by the link; a removal of a part not there
takes no page. Anything else
in `ext/`, a link among them, is left as it is, and counts as installed
for no need: the run is refused before anything changes, naming it, for
every plugin named and every part it needs. With none named,
`remove --all`, `update` and `verify --server` read only what may be a
plugin's -- an entry named as a plugin of the checkout, or a directory
holding a `PLUGIN` or a `VERSION` -- the first two
passing over each that
is no install, saying so, `verify` saying it is none; the rest of `ext/`
is the site's, its own scripts, and is not read. The virtualenv and the
stage `/plugins` serves are no plugin's, and go only with an install
removed (S8).

**S21. Under `DESTDIR`, nothing is written outside it.**
An install staged under `DESTDIR` writes only there. Xymon's own staged
install may leave `$XYMONHOME/etc` as an absolute link to where its
configuration goes once installed, `/etc/xymon` on Debian and with the
RPM, and a packager may link any directory of the stage the same way.
Every directory the install writes to or reads a setting from -- `ext/`,
`etc/`, `tasks.d/`, `MANDIR`, `$PREFIX/libexec`, `$PREFIX/bin` -- is
followed inside `DESTDIR`: a link to an absolute path from `DESTDIR`, a
relative one from where it lies, a `..` stopping at `DESTDIR`, a chain of
links each in turn, a link higher up the path as well as at its end; a
link that cannot be read stops the run. Below those directories, a link in
the place of a plugin's directory or of the stage's `plugins/` is removed,
never followed -- what an update sets aside goes in a directory it makes
new (S7) --, and a command is written in place of a link, never through it. No virtualenv is made or
used under `DESTDIR`: it belongs to the installed system.

**S22. A socket a plugin makes for another program is in Xymon's runtime
directory.**
The API's sockets are in its directory there,
`$XYMONRUNDIR/xymonapi/`, or `$XYMONSERVERLOGS/xymonapi/` when
`XYMONRUNDIR` is empty, as Xymon does: `relay.sock` for the web server,
and `local/api.sock` for the server's own programs, `local/` being the
Xymon user's and its group's alone; the clients look for it there. The install writes that path into
the web server snippets, asking Xymon's `xymoncmd`, which loads the
server's configuration as xymonlaunch does for the API -- its includes,
its variables, its defaults; under `DESTDIR`, or where `xymoncmd` is
missing or fails, read from `xymonserver.cfg` and then the files of
`xymonserver.d/`, the last `XYMONRUNDIR=` line, quoted or not. Where that
gives no absolute path -- a variable read without Xymon -- the snippets
keep `@XYMONRUNDIR@` and the install says so. The API makes its directories there when it starts and
takes them away when it stops.

**S23. A plugin's SELinux module grants nothing until the admin says so.**
A plugin that needs a SELinux rule ships it as a module, `NAME.cil` among
its server files, named in its `PLUGIN` file's `selinux:` line. Where
SELinux is active, `install --server` loads it with `semodule` and says how
to switch it on: what it grants lies behind booleans, off. `remove --server`
removes it, and an update to a version without one: the module named after
the plugin, never one the installed `PLUGIN` copy names otherwise. Under
`DESTDIR`, or where SELinux is not active, nothing is loaded. The module
lies outside the plugin's directory: deleting `ext/NAME` by hand leaves it
loaded, inert while its booleans are off, and so does a removal that then
finds no directory to remove (S20): `semodule -r NAME` takes it away.

### Knowing what is installed

**S15. `status` says what is installed.**
`status --server`, `status --client` and `status --tools` say, for each plugin of the part, or
those named: whether it is installed, the version installed, from its
`VERSION`, a release tag read as its `X.Y.Z`, or that an install of it
was cut short (S20); on the server, whether its
task is on; and the version of the copy run from -- a checkout, or
releases unpacked side by side -- said as "this copy has", marked newer
when it is, and, at the same version, said to have other code when its files differ
from those `MANIFEST` says were installed (S29), naming the update. A name that is no plugin is refused. `status` changes nothing. It
says them by section, each always there, empty or not: the Xymon server,
its own client tree -- the one its `XYMONCLIENTHOME` names -- and the
person's tools; `--server` and `--tools` keep to theirs, and `--client`
with `XYMONHOME` naming a server to its own client tree (S36). A standalone
client's tree (S35) is said as a server's: with no
part named, one `XYMONHOME` names stands for the server's sections, and
without `XYMONHOME` each one found (S25) has its own after the servers';
`--client` keeps to them. One found that a client verb refuses -- a
server's own is never one apart (S25), one in doubt is -- is said
with why, and not read.

### Running the command

**S17. With no verb and no terminal, nothing is done.**
Run with no verb, its input or its output not on a terminal, the command
prints its usage, exits 2 and changes nothing, settings given or not: a
script that forgot its verb installs, enables and removes nothing.

**S27. With no verb on a terminal, the command shows, then offers.**
Run with no verb, its input and its output on a terminal, it says what it
found: the Xymon installation, by S25 -- declined, the dialogue goes on
with the person's tools alone -- each plugin installed there with
its version and, for one with a task, whether it is on, and the person's
tools, each in its section, the server's client too; beside each plugin
what `verify` finds broken or untidy in it (S30), and in each part what
a plugin gone left there. It then offers only
what applies, one line each, the plugins others need first: install a
plugin on the server, with what that part does, by the `server-short:`
line of its `PLUGIN`, and the plugins it needs named; turn one
on or off; update the server's plugins, saying which it repairs; remove
one that no installed plugin needs; take away what a plugin gone left
(S31), with `--yes`, what is left being shown already and the command
asked once; install a plugin's tools, said by its `tools-short:` line; update
them, the same; take away what one left there; or nothing, the default, Enter. It prints the command those
answers spell, the installation in it by `--xymon-home`, asks
`Proceed? [Y/n]`, runs exactly that command and nothing else, and stops;
after an install of a plugin with a task it offers enabling as a second
command, printed and asked with `[y/N]`, so that Enter declines it (S5).
Off a terminal, S17.

**S24. One command: a verb, and the part it acts on.**
`xymon-plugin` takes a verb -- `install`, `update`, `enable`, `disable`,
`remove`, `status`, `verify`, `outdated`, `clean` -- and the part it acts on, `--server`,
`--client` or `--tools`, one at a time. An action of the `install.sh` it
replaces, as `install-server` or `install-client`, is refused, naming the
new form. Without a part named, on a terminal, the server part is said and
acted on, but a client's tree named is refused, on a terminal too, the
command given with `--client`; off a terminal, a verb that changes
something is refused; `status`, `verify` and `outdated` cover every part,
the server's, a standalone client's tree and the tools. `install`, `remove` and `clean` need a
plugin named, or `--all`. `install` refuses a plugin installed already, and
`update` one that is not; `--all`, and a plugin one needs, pass over those
installed, saying so. `enable` and `disable` refuse the tools, which have
no task, and a plugin named with no task in the part. Run as
root, a verb that changes the tools is refused
unless `DESTDIR` or `PREFIX` is given; `verify` and `outdated`, which change
nothing, are not. Two parts named together are refused, `status`, `verify` and `outdated` saying
what they cover with none, another verb giving the
commands to run, one per part. `update` says what it updated, without the help a
first install gives.

**S25. A run changes one Xymon installation, named or confirmed.**
`XYMONHOME`, or `--xymon-home PATH`, which wins when both are given, names
it, checked against its marks (S18); running under `xymoncmd`, which sets
it, counts as naming it. Not named, on a terminal, the installations found
are proposed, those of the part's kind: the one found, Enter for yes;
several, listed, the one used last for that part as the default, said
when it is gone, and none otherwise; for `--client`, the standalone client
trees found, and the one used last while its marks hold.
Detection reads the packages' usual paths, Homebrew's, the trees of a
running `xymonlaunch` and the `xymon` user's home, not the current
directory; it compares trees by their resolved path, and tells a client
tree a server found names as its own as part of that server. Off a
terminal, not named, a verb that changes something is refused, listing the
trees found; `status` lists every installation found and what it holds,
and never asks. A `XYMONHOME` that is a server's own client tree -- the
`../server` beside it, or a server found, naming it as its
`XYMONCLIENTHOME` -- is refused, naming that server and the forms that
name it, `--server` or `--client` (S36); with `--client`, so
is a client tree that may be one: a `../server` beside it, a server's,
that names another tree or none the command can read, a server found
that names its client tree with a variable, or a
`xymonserver.cfg` in its `etc/`, the refusal saying which. That
`../server` is the one beside the tree's resolved path, however the tree
is named: relative, with `.`, or through a link.
`XYMONCLIENTHOME` itself is never read: a server's environment sets it
too. Before anything
changes, the run says the target, the part, and what chose them: named, or
detected and confirmed. The installation a run changed is remembered once
it has done its work -- not by a refusal, nor by `verify` -- as the one
used last for its part, a file per part, `installation-used-last-server`
and `installation-used-last-client`, in the person's
`$XDG_CONFIG_HOME/xymon-plugin/`; under `sudo`
it is read from `SUDO_USER`'s and not written.

**S26. The Python environment comes with install and update.**
There is no verb for it: `install` and `update` make or complete the
virtualenv beside the plugins a plugin's modules need, and those it does
without that its `PLUGIN` names as optional, `venv-note` saying what they
add: `tools-optional-modules: fastembed numpy` for a local search index,
where search asks the server without them. On a terminal they
ask before fetching modules from PyPI; off one they fetch none unless
`--venv` is given, and say how to make it; `PYTHON=` names a Python that
has the modules already, from which it is made with nothing fetched; under
`DESTDIR` none is made or used (S21). One that cannot be made does not fail
the install, which says how to make it. `enable` refuses a plugin whose
Python -- `XYMONAPI_PYTHON`, else that virtualenv, else `python3` -- lacks
the modules it needs, or has one older than a `NAME>=X.Y` line of the
plugin's `requirements.txt` asks, naming what makes them, and `status`
says so. A Python with an older one is not taken for the virtualenv
either, and a virtualenv with one is offered the newer. The versions
`requirements.txt` asks are the oldest the plugin's tests pass with: CI
runs them with exactly those.

**S28. A plugin writes only where this rule says.**
An install writes a plugin's files under its directory, and outside it
only: its task link, `etc/tasks.d/NAME-server.cfg` or a client's
`etc/clientlaunch.d/NAME-client.cfg`, or, for a server's own client tree,
the server's `etc/tasks.d/NAME-client.cfg` (S6, S13, S36); the link to its manual page
in `MANDIR` (S20); its command in `$PREFIX/bin` (S4); its copy in the stage
`/plugins` serves (S19); the virtualenv beside the plugins (S26); and its
SELinux module (S23); a client part, only its directory, its manual
page's link and its task's link (S35). The command itself writes, besides, only the
installations used last (S25), and while an install or an update runs
the directory `ext/.xymon-plugin.NAME` where it sets files aside, and
`ext/NAME/.xymon-plugin-in-progress`, left after one cut short until the
next resumes (S7, S20): no file of its own, not even a
temporary one, anywhere else. While it runs, a plugin writes only: its
sockets, in its directory of Xymon's runtime directory (S22); its log, in
Xymon's log directory; and what its `PLUGIN` file declares -- a `data:`
line for each directory it keeps for the administrator or the person,
which outlives it (S10), and a `writes:` line for each file of another
program that one of its commands changes, the file, then that command in
parentheses: `writes: ~/.claude.json (xymonapi-mcp register)`. A `data:`
path is `$XYMONVAR/NAME/`, `$XDG_CONFIG_HOME/NAME/`, `$XDG_CACHE_HOME/NAME/`
or `$XDG_STATE_HOME/NAME/`, `NAME` being the plugin's own or that of a
plugin it needs (S3); a `writes:` path names one file. A line that does
neither is refused before anything is installed. An install, an update
and a removal leave nothing anywhere else: the test compares the whole
tree, and the person's home, before and after. What a plugin writes while
it runs is declared here, and checked by its own tests with a scratch
home.

**S29. An install records what it wrote.**
The last step of an install or an update command -- once every plugin it
installs, and the virtualenv they share, are in place -- writes `MANIFEST` in each
plugin's directory, beside `VERSION` and `PLUGIN`: one line for each file
and link it wrote, its fields separated by tabs. A file is
`file⇥CKSUM SIZE⇥PATH`, `CKSUM SIZE` what `cksum` gives, with `⇥admin`
after the task file and the web server snippets, the administrator's to
edit (S7); a link is `link⇥PATH⇥TARGET`. A path in the plugin's directory
is given from it, `app.py`; one outside, as installed, without `DESTDIR`:
each file of the copy `/plugins` serves (S19), the command (S4) and the
manual page's link (S20), each only when the install wrote it. The task
link is not in it: it is a state, on or off, that `enable` and `disable`
change after the install (S13); nor a
SELinux module loaded, a state of the system's policy, its `.cil` file
being one of the directory's (S23). `MANIFEST` lies in the plugin's
directory, so removing that directory removes it; and in a directory the
Xymon user can write, so it decides nothing alone: a removal takes away
what S20 allows, no more. A plugin installed before it existed has none
until it is updated. One whose lines would be the same, no virtualenv made,
removed or filled by the command, is left as it is: the code is the same,
and what watches the file (xymonapi, xymonapi-mcp) does not restart for
nothing. The `data:` and `writes:` lines of the `PLUGIN` copy
say what the plugin's own commands may have written since (S28).

**S30. `verify` says what differs from what was installed.**
`verify --server`, `verify --client` and `verify --tools` change nothing. They say, one line
each, `broken:`, `untidy:`, `edited:`, `note:` or `ok:`, the plugin, what differs,
and the command that puts it right:
`broken: xymonapi: app.py changed: ./xymon-plugin update --server xymonapi`.
For each plugin of the part, or those named, what its `MANIFEST` (S29)
and its files disagree on; a part with no plugin installed says `no
plugin`, as `status` does. Broken, as the plugin may no longer do what was
installed: a file missing; a file changed that is not the administrator's
to edit; a link outside the directory gone, or pointing elsewhere; a file
in the plugin's directory that the manifest does not name and that can run
or be imported -- one with an execute bit, or named `*.py`, `*.pyc`,
`*.pth`, `*.so` or `*.sh` -- and a `__pycache__` there, the launchers
writing no bytecode, so that the code Python runs is the code installed;
any file in the copy `/plugins` serves that the manifest does not name,
as it goes to other machines; the task link, which `MANIFEST` leaves out,
there and pointing elsewhere than the plugin's task file; a SELinux module
its `PLUGIN` names not loaded where SELinux is active, by `semodule -l`;
and a Python module the plugin needs missing from the Python it runs with,
or older than its `requirements.txt` asks -- what is checked of the
virtualenv, which `MANIFEST` leaves out. Untidy, as it works all the same:
a `NAME.new` or `NAME.old` an update left beside an administrator's file
(S7), "this version's beside yours" or "yours before the merge", to
compare and remove; a stale set-aside directory of the plugin, or of
one whose directory is gone, or one at its name not marked (S7); any
other `NAME.old`, at any depth, which an update keeps
(S7); any other file in the plugin's directory that the
manifest does not name; a link to its task file under another name than
its own (S6), read all the same, to rename with the `mv` it says;
and a plugin with no `MANIFEST`, installed before it was kept, which an
update records. A file the manifest marks the administrator's is said
edited, and is neither. Then, with no plugin named, what is left in the
part that belongs to no plugin installed, untidy too: a task link, a
manual page's link or a command of a plugin whose directory is gone (S9);
a staged copy of one; a stage or a virtualenv with no plugin beside it.
A module the plugin names as optional (S26) is no finding when missing:
a `note:` line says what it adds, counted for nothing, as an edited file
is; one there and older than `requirements.txt` asks is broken all the
same. Each line names `update` for a plugin's files, `update --venv` for
its modules, and `clean` for what is left. It exits 0 when nothing is broken
or untidy, 3 when something is broken, whatever else is untidy, and 4 when
something is untidy and nothing broken. It needs no terminal, and, as
`status`, covers every installation found when none is named (S25),
the standalone clients' too. In a client's tree (S35) it checks the
same, but what a client part never has: a copy `/plugins` serves, a
virtualenv, a SELinux module, a web server snippet; what is left there is
a task link or a manual page's link that points into the directory of a
plugin of that tree that is gone.
`MANIFEST` lying where the Xymon user can write, `verify` finds what was
changed by mistake or left behind, not what someone able to write there
and to rewrite `MANIFEST` too has hidden.

**S31. `clean` takes away what no installed plugin owns.**
`clean --server`, `clean --client` and `clean --tools` need a name, or `--all`, as `remove`
does (S24). They remove what `verify` lists as left (S30), and nothing
else: never a file in an installed plugin's directory, which `update`
replaces (S7), nor anything a `data:` or `writes:` line names, which is
the administrator's or the person's (S28). A name given is that of a
plugin that is gone: a plain file name (S20), refused when a plugin of
that name is installed in the part, naming `remove`, or is an install
cut short there, naming `update` (S20); it need not be in the
checkout. What is left of it is what bears its name: its task link, its
staged copy, and the links and commands that point into its directory.
`--all` covers every such name, and the stage and the virtualenv when no
plugin is installed beside them. A thing is removed only when it is
provably a plugin's, as S20 says of a removal: a link only if it points
into a plugin's directory that is gone, a command only if it is, byte for
byte, the one an install writes for such a directory. It first says the
target (S25) and lists what it will remove. On a terminal it asks
`Proceed? [y/N]`, so that Enter removes nothing. Off one it removes
nothing, and says so, unless `--yes` is given. What it could not prove a
plugin's it leaves, and says. Its exit says the state after it, as
`verify`'s does: 0 when nothing is left, 4 when something is -- nothing
removed off a terminal without `--yes`, an answer N, or a thing left
unproved.

**S32. `outdated` says what a newer release would update.**
`outdated` reads, as `status` does (S15), the parts installed -- every
one when none is named: the Xymon servers', the standalone clients' trees
and the tools'; with one named, that one -- and says of each plugin installed the version
installed against its latest published release on GitHub: up to date; a
newer one released, with the update that takes it; installed newer than any
released; none released; or that its `VERSION` cannot be compared --
missing, a link, unreadable, in a directory this user cannot enter, holding
no version -- with what fixes it when the cause is known (a `chmod` named
with whoever owns what is closed, an `install` or `update`), how to find it
otherwise, never what it holds; a client's tree it does not read, as
`status` says of one (S25), is said, as a `VERSION` that cannot be
compared. Every directory there that it cannot enter
is said, but the virtualenv and `/plugins`' stage, the installer's own; so
are plugins it cannot list, their directory or one above it closed. It
changes nothing. It reads the releases from GitHub: with `gh` when it
answers, drafts left out as an anonymous reader does not see them;
otherwise GitHub's API, anonymously, through `curl` or `wget`, at most 60
pages of a hundred, as many as GitHub answers, from one address, in an
hour; each request of `curl`, and of GNU `wget`, bounded in time, one that
runs out of it being GitHub not reached -- `gh` has no such bound, and
`XYMON_PLUGINS_NO_GH` leaves it out; `GH_TOKEN`, when set, is given to
`curl` on its standard input, never on its command line. It ends with 1,
saying why, when none reaches GitHub or when there are more releases than
that, before any `VERSION` is read. Otherwise it ends with 7 when a
`VERSION` could not be compared, every line said; else with 6 when it said
of a plugin that a newer release exists, and with 0 when it said of none --
for a script or a Xymon task to read.

**S33. The plugins column says it on the server and on a client.**
The `xymon-plugin` plugin installs, off as every task (S5), a task that the
administrator turns on with `enable` (S13): once a day, after a wait drawn
at random up to 6 hours -- after which, when it waited, it runs again from
its file, in the same process, so that an update meanwhile has its code
send --, it runs the
installer installed beside it,
`outdated --server` (S32) without `gh` (`XYMON_PLUGINS_NO_GH`), which no
time bounds -- xymonlaunch's `MAXTIME` stops the task, not what it started
-- and sends the server's status `plugins` -- for `MACHINEDOTS`, its name
in `xymonserver.cfg` and `hosts.cfg`, not `MACHINE`, which may be the
system's -- valid 31 hours, with `outdated`'s lines, each plugin's with
its colour's icon (`&green`, `&yellow`), and a first line counting the
plugins and naming those behind: green for 0, no newer
release published; yellow for 6, 7 or any other status, saying which;
nothing for 1 -- GitHub not reached, or `outdated` unable to run -- so that
the status there stays, and goes purple once 31 hours have passed since it
was sent, as it also does when xymond's restart stops the task while it
waits. What it does goes to its log, `xymon-plugin.log`; a status it could
not send, or that xymond did not keep, read back, ends it with 1.
After an `install`, `update` or `remove` of a server part that changed an
installation -- a plugin installed, updated or removed, not a refusal nor
one passed over or not there --, and after an `enable` of
`xymon-plugin`, on already or not -- the way to have the column sent now,
a release published since its last run among what it says --, the command sends the column at once while that
task is on, its link in `tasks.d` there: once, at its end, it runs the
installed task's script with no wait, under the server's environment
(`xymoncmd`, which reads `xymonserver.cfg`), and says what it sent. When it
cannot -- GitHub not reached, the script gone, `xymoncmd` missing, the
status not kept -- it says so and goes on: the column is refreshed, the
command's own result does not depend on it. Under `DESTDIR`, with the task
off, after a run that changed nothing, after `enable` of another plugin or
`disable`, or once `xymon-plugin` itself is removed, nothing is sent; the
column then goes purple once 31 hours have passed, as before.
On a standalone client (S35), `xymon-plugin`'s client part installs the
same script and a task of its own, `client-task:`, off until `enable
--client xymon-plugin`: the same run, with `outdated --client`, under the
client's environment -- `xymonclient.cfg`, and `MACHINEDOTS` as
`runclient.sh` gives it, its `--hostname` or the system's name --, sending
the client's status `plugins`, its log `xymon-plugin-client.log` in
`XYMONCLIENTLOGS`. Each client asks GitHub itself, anonymously, which
GitHub allows 60 times an hour from one address. The task writes, each
run before it waits, the name it was given in
`$XYMONTMP/xymon-plugin.host`; the run the installer starts does not. The column is sent at once
as on the server, after a `--client` run that changed the client's tree
and after `enable --client xymon-plugin`, under `xymoncmd` reading
`xymonclient.cfg`, with the name that file holds, or, before any run, the
one `runclient.sh` puts in its `clientlaunch.NAME.pid`; with neither,
nothing is sent, said. On a server as on a client, a status goes to
`XYMSRV`, or, where that is `0.0.0.0`, to each server `XYMSERVERS` names,
each read back for that host and that column alone: one that did not keep
it is said in the log and ends the run with 1; kept blue, the column
disabled, it is said and does not; one that refuses to be read (xymond's
`--www-senders`), its board read back empty for every host, is said and
does not, whether it kept it then not known.

**S34. A task says what it needs to what can wait for it, and checks the
rest itself.**
A plugin's task names in `NEEDS` only a task its launcher knows when it
reads the task: on the server, one of Xymon's own `tasks.cfg`, defined
before the line that reads `tasks.d/`, as `xymond` -- never another
plugin's: xymonlaunch resolves `NEEDS` while it reads, so a task read after
is unknown at the first load and whenever its plugin is off -- the
dependency then dropped, "unknown dependency" logged --, and, resolved, a
task that stops by itself at each update (S7) would stop the one needing it; a task of another part, when one
comes, one of that part's launcher (`clientlaunch.cfg`'s `client` on a
client), or none where its launcher has no such thing (cron, launchd).
A `NEEDS` in a client part's task is the plugin's choice, its pitfalls said
in CONTRIBUTING.md: a server's own client tree taking client parts (S36),
one file is read by two launchers that know different tasks, a task only
one knows dropped by the other; and `NAME-client.cfg` is read before
`NAME-server.cfg`, so its own server task is unknown at the first load.
What no launcher can wait for -- a server or an API elsewhere, files that
may not be there -- the task checks itself before its work: what is
missing is said, and the run ends with 1, for its launcher to start it
again at its next time.

**S35. A client part goes into a standalone client's tree, by its owner.**
`--client` installs, updates and removes a plugin's client part, its
`client-*` lines, in a standalone Xymon client's tree (S18, S25): its files
under `ext/NAME/`, with `VERSION`, its `PLUGIN` copy and its `MANIFEST`
(S20, S29); its manual page, `client-manual:`, kept there and linked from
`MANDIR` when that can be written and the page's name is free there
(S20), else not, the command saying so.
Its task, `client-task:`, is installed off and turned on by `enable
--client`, as a server part's (S5, S6, S7, S13).
Nothing else is written: no copy in the stage `/plugins` serves,
no virtualenv (`--venv` with `--client` is refused), no web server snippet
and no SELinux module; nor is a client part staged under `DESTDIR`, which
is refused. A plugin named with no client part is refused, and one whose
`client-files:` or `client-manual:` names a file its directory lacks, or
a link, before any plugin is installed. A client part's needs,
`client-needs:`, are client parts (S3). `install`, `update` and `remove`
replace or take only a directory an install left, as on the server (S20):
`VERSION` and `PLUGIN`, naming the plugin and a client part, plain files;
only such a one counts as installed, for a need too. Any other in `ext/`
is left as it is, an install cut short resumed as on the server; `update` with
none named passes over a plugin this checkout lacks, saying so. Before anything
changes, the run is refused unless the person running it owns the tree's
`ext/`, root as any other, naming the owner: the files of a part are
written by whoever owns its tree, so that the same person updates and
removes them. `status` and `verify`, which change nothing, read a
client's tree as a server's (S15, S30), whoever owns its `ext/`, and
refuse the trees the other verbs refuse: a server's tree naming no client
tree of its own, a server's own client tree named as a client's, one in
doubt; a server's own is read through its server (S36). `outdated` reads a client's tree as a server's (S32),
and `clean --client` takes away what `verify` says is left there (S31),
run as the other verbs that change something.

**S36. A client part goes into a server's own client tree too.**
A Xymon server has a client tree of its own, the one its `xymonserver.cfg`
names as `XYMONCLIENTHOME`, through which the server's host is monitored.
`--client` with `XYMONHOME` naming the server installs, updates, removes,
turns on and off, and reads a plugin's client part there, as on a
standalone client (S35); that tree named itself is refused, giving this
form (S25). `XYMONCLIENTHOME` is read as Xymon's installs write it, an
absolute path, spelt once as the server's `XYMONHOME` is -- its links
kept, as Homebrew's `opt/`, which names the current version --; a server that names none, a variable --
which nothing here runs the server's programs to read --, a path not
absolute, a directory that is not there, one without a client's marks
(S18), or the server's own tree, is refused, saying what it read. Before a verb changes
anything: a server with no `ext/` of its own, which every Xymon server
install makes, is refused as an install incomplete; a client tree with no
`ext/` -- which Xymon's own installs make, a directory or, as Homebrew's, a
link to one -- is refused, giving the commands that make it, or what a
link names; one that is the server's own `ext/` under another name is
refused, as the client part would take the server part's directory; an
`ext/` -- what a link names -- owned by another than the owner of the
server's `tasks.d/`, where its task's link is written, is refused: one
person writes both, as S35 has it, and the part's task runs as the
server's xymonlaunch; a `chown` is given only for a directory, not for
what a link names, which the client tree's owner chose. That person
runs it. A verb that
reads finds a tree with no `ext/` empty, saying nothing. Under `DESTDIR`,
as S35, a client part is refused.
Its task is started by the server's xymonlaunch, which does not read the
client's `clientlaunch.cfg`: installed off, `enable --client` links it from
the server's `tasks.d/` as `NAME-client.cfg` (S6), beside a server part's
`NAME-server.cfg`, the server's `tasks.cfg` the one read and touched (S13);
its `@XYMONHOME@` is the client tree, and its `@LOGDIR@` the server's
logs, `$XYMONSERVERLOGS`, as Xymon's own task for that client has them.
`xymon-plugin`'s client part does not go there: the server's copy, the
same installer, manages that tree. Named, it is refused, with the
commands that remove a copy left there; with none named, passed over. A
client part there needing it is installed only while the server has
its copy, and that copy is not removed while one there needs it.

### Getting the code

**S11. `stable` is code every test passed.**
CI moves `stable` to a commit of `main` once every test passed on it, forward
only; installing from `stable` installs tested code.

**S12. The installer runs on every machine a plugin goes to.**
`xymon-plugin` and the tests keep to Xymon's portability rules, but the one
against Python, which every plugin but the installer needs, and the one against the
`rrdtool` command, which the API runs to read the RRD files.

## Planned

Rules decided but not yet tested; each is numbered in the pull request that
brings its test.


- **A plugin has up to three parts.** Each is declared by its own lines of
  `PLUGIN`, and a plugin has one, two or all three. The server and client
  parts are its Xymon parts:

  | part | lines | where | installed by |
  |---|---|---|---|
  | tools | `tools-*` | any machine, under `PREFIX` (`~/.local`) | the person, as themselves |
  | server | `server-*` | a Xymon server's tree, `ext/NAME/` | the user that may write it, usually root |
  | client | `client-*` | a Xymon client's tree, `ext/NAME/`, its task started from a standalone client's `clientlaunch.d`, or, for a server's own client, from that server's `tasks.d` | the same |

  A client tree no server names is a standalone client, a monitored host;
  a server's own client tree is S36's. A client part names what it
  needs with `client-needs:`, as S3 has the other parts do; a need the
  target cannot hold, as a server part on a standalone client, refuses the
  install, saying why (S35 for a standalone client). Once built, this
  replaces S4's sides, and the `side:` lines of today's `PLUGIN` files, which call the
  tools part "client", are removed: the parts a plugin has are those its
  lines declare. A client part keeps its runtime files in `$XYMONTMP/NAME`
  and its logs in `XYMONCLIENTLOGS`, the places Xymon gives a client; a
  server part keeps its runtime files in `XYMONRUNDIR` (S22) and its logs
  in Xymon's log directory. The checks under `checks/`, copied into place by hand today, each
  move under `plugins/` as a client part when they get a `PLUGIN` file.
- **A client tree that may be a server's own** (S25) is asked about, once
  the command can ask, rather than refused.
- **One command, read as a sentence.** `xymon-plugin` (S24) takes a verb
  and the plugins it acts on; still to come is `connect`:

  ```sh
  ./xymon-plugin install xymonapi
  ./xymon-plugin enable xymonapi
  ./xymon-plugin disable xymonapi
  ./xymon-plugin update xymonapi
  ./xymon-plugin remove xymonapi
  ./xymon-plugin status
  ./xymon-plugin connect https://xymon.example.ch
  ```

  With no plugin named, a verb acts on every plugin of the installation it
  targets (below), but `install` and `remove`, which need a plugin named,
  or `--all`. `install` refuses a plugin already installed, and `update`
  one that is not: once built, `update` does what S7 says of installing
  again.
  The Python environment a plugin needs is S26's. It is POSIX `sh` and
  needs no `make`.
- **`connect URL` links a part to a source.** With no selector it means
  `--tools`, unlike the other verbs. For the person's tools it links their session to an API: one plugin's
  `PLUGIN` has a `connect:` line, `xymonapi`'s, which gets the token, the
  password asked once; each plugin that hooks onto that link has an
  `on-connect:` line, run after it in the order of their needs, as `xymonapi-mcp`'s registers the AI
  tools found. Both name a file of the plugin's tools part, run with the
  URL, so that the command itself still names no plugin. On a terminal, a
  menu offers the plugins with an `on-connect:` line, those installed
  ticked; off one, those named on the command line, else those installed.
  Tools already installed are kept, and the command says when the source
  offers a newer version. A failure stops the run where it happens: no
  hook runs without a token, and a hook that fails stops the ones after
  it; what was installed stays. `connect` for the tools part is refused as
  root, whatever `PREFIX` says: a link is the person's. With `--client`, `connect URL` links a
  client to the Xymon server it takes its part from; with `--server`, a
  server to a source of its own, a central server or a mirror; the URL is
  kept in that tree's `xymon-plugin.cfg`. How a client authenticates to
  its source waits for the repository plugin (Later, #29).
- **The parts are asked for, or named.** `--server`, `--client` and
  `--tools` name the parts a verb acts on, for every verb. `enable` and
  `disable` refuse a part with no task, as the tools, when it is named,
  and pass over it when it is not. `--server` and
  `--client` may be given together; `--tools` is given alone. Without them,
  on a terminal, the command asks which parts, offering those the
  installation a run targets (below) takes and the plugin has: on a
  server's tree, its server part, and its client part into the server's
  own client tree; on a standalone client's tree, the command is refused,
  giving it with `--client` (above). When only one applies, it says
  which, and does not ask. Off a
  terminal, a verb that changes a Xymon part needs them; `status` without
  them covers every part, on a terminal as off one, every installation
  found listed unless one is named; `status` never asks for one. A part the plugin does not
  have is skipped when not named, and refused when named, saying why. On a
  server, `--client` means the server's own client tree; `--server` asked
  of a standalone client's tree is refused. The tools part is never
  installed with the Xymon parts: it belongs to the person, under
  `PREFIX`, while they belong to whoever owns the Xymon tree, often root,
  and it is installed only when asked -- `--tools`, `connect`, or the
  dialogue. Run as root, a verb that changes the tools part is refused,
  unless `DESTDIR` or `PREFIX` is given; `connect` and `status` have their
  own rules (above, below). A refusal comes before
  anything changes. A machine with no Xymon installation installs no Xymon
  part, and says that the tools are installed with `--tools` or `connect`.
- **A run changes one Xymon installation (S25)**; still to come: the
  doubt whether a client tree is a server's own -- `../server` there but
  naming another, which the command refuses today, or a server's
  `xymonlaunch` running -- which the command asks; and, for `--tools` and
  `connect --tools`, the installation proposed too, whose local socket the
  dialogue offers as the API's URL.
- **With no verb on a terminal, the command shows where things stand
  (S27)**; still to come: connecting this machine to an API among the
  offers, with `connect`.
- **The code comes from a source.** `install` and `update` take a
  plugin's code from a source: a Xymon server, through its API or its web
  server; GitHub, the plugin's releases; or one named with `--source`, a
  checkout or a URL. With none named, the tools part takes it from the
  Xymon server `connect` connected the machine to; a Xymon server's
  parts, from the source `connect --server` linked it to, else GitHub; a
  standalone client's part, from the Xymon server `connect --client`
  linked it to, or, the first time, the one it reports to, whose URL is
  asked, as `XYMONSERVERS` gives an address and no URL. A source named with `--source` is trusted: what it
  gives is installed unchecked, and the first line says so. Under
  `DESTDIR`, the source is the checkout `xymon-plugin` runs from. Where the
  default source can give nothing -- unreachable, no release, or, for the
  tools, no server connected yet -- that checkout is offered, `[y/N]`, on
  a terminal; off one, `--source .` names it. The plugins offered, and
  what is newer, are the source's.
- **Code no proof checks follows a setting, `trust`.** From a source not
  named, code that matches no release on GitHub -- every plugin's today,
  as none has a release yet -- is handled as `trust` says:

  | `trust` | code no proof checks |
  |---|---|
  | `github-only` | refused, unless `--force` |
  | `ask` | asked, `[y/N]`, on a terminal; refused off one |
  | `connected-server-warn` | from the connected server -- its certificate checked, its token -- installed, with a warning |
  | `connected-server` | from the connected server, installed, with no warning |

  It is `ask` for a Xymon server's and a client's parts, and
  `connected-server-warn` for the person's tools, until set otherwise.
  Four guards stand against a compromised Xymon server, each on until the
  setting turns it off: code that differs from the GitHub release of the
  same version is refused; so is code that differs from what was
  installed before under the same version, whose digest is kept; a block
  list the project publishes refuses the versions it names, and `status`
  says when one is installed; and a command stops a server serving
  plugins, or sets a machine to `github-only`. Where GitHub cannot be
  reached, the first and the third are not checked, and `trust` decides,
  as for code no proof checks. `connected-server-warn` and
  `connected-server` handle code from a source other than the connected
  server as `ask` does. The setting and the digests are kept in
  `$XDG_CONFIG_HOME/xymon-plugin/` (`~/.config/xymon-plugin/` by default)
  for the person's tools, and in
  `$XYMONHOME/etc/xymon-plugin.cfg` for a Xymon tree's parts. The
  installation used last, which the dialogue proposes among several, is
  kept in the same directory of the person who typed the command --
  `SUDO_USER`'s under `sudo`, else the account's that runs it; when it is gone, there is no default, and
  the command says so. `status --tools` run as root reads the tools of
  that person too.
- **Open, to decide.**
  - where the search index lies on a server: `$XDG_CACHE_HOME/xymonapi-rag/`
    today, which the item above allows as `data:`, or under `$XYMONVAR`,
    where Xymon keeps its own;
  - how much of "while it runs" a test can check: plugin by plugin, its
    tests run with a scratch home and compared, and the rest declared;
  - how a client authenticates to its source: with the repository plugin
    (Later, #29);
  - the option that answers "a standalone client" when the command asks;
  - the setting by which a server's administrator allows serving an
    archive no proof checks;
  - how each guard is turned off -- by `trust` or a setting of its own --
    and the command that sets `trust`, stops a server serving plugins, or
    sets a machine to `github-only`;
  - a second plugin with a `connect:` line;
  - `connect` given a URL on a server: whether it still asks for the
    installation; and whether `connect` with no URL exists;
  - in `connect`'s menu: an installed plugin unticked, and where a ticked
    plugin not installed comes from;
  - whether the checkout, accepted with `y`, counts as a source named,
    and so trusted;
  - `install --all`, and a plugin needed, when some are installed already;
    whether `install` and `update` refuse part by part; S3 and S8 part by
    part, for installing and removing;
  - for a server's own client, which tree's `xymon-plugin.cfg` keeps its
    source;
  - whether a standalone client's server URL is given only by
    `connect --client`;
  - who owns the files written for `SUDO_USER` under `sudo`.
- **Removing the directory by hand removes everything of that part.**
  Beyond the task (S9; for a client part, its link in `clientlaunch.d` or
  in a server's `tasks.d` is passed over the same way, which a test on a
  standalone client checks), what each program reads it reads through the place
  below, so that after `ext/NAME` is deleted Xymon no longer applies the
  plugin's settings, and the API no longer serves it:

  | What | Lives in | Seen by its reader through |
  |---|---|---|
  | settings | `ext/NAME/xymonserver.cfg` | a link in `etc/xymonserver.d/`, which Xymon reads after `xymonserver.cfg` |
  | manual page | `ext/NAME/` | a link in `MANDIR` |
  | what `/plugins` serves | the release archive the part was installed from, or, where allowed, the one built for a checkout, kept in `ext/NAME/` | the API, serving that archive at `/plugins/NAME` |
  | Python modules | `ext/NAME/venv/` | the plugin's own launcher |

  A plugin that needs Python modules beyond the standard library has its
  own virtualenv, in its directory, instead of the one shared today: none is
  left behind by a plugin removed, at the cost of a module two plugins need
  being installed twice. The test installs every plugin, enables it, deletes
  `ext/`, and checks xymonlaunch, `xymoncmd`, `apachectl configtest` and
  `nginx -t`.
- **What `/plugins` serves can be checked against the repository.** Each
  release of a plugin, its tag `NAME/vX.Y.Z`, has an archive that CI builds
  from that tag -- reproducibly, so that the same tag always gives the same
  bytes -- attests, and attaches to the release. A server serves those
  bytes, one archive per plugin, at `/plugins/NAME`: the archive it
  installed, not one built on the spot. `install` from a server it was not
  told to trust with `--source` checks the archive before it installs, by any proof that does not come from that
  server: its attestation, verified with `gh`, `cosign` or Python's
  `sigstore`, with no key kept, as the attestation is signed for the CI run
  that built the archive; or the same archive rebuilt from the release tag
  in a copy of the repository, from any mirror, the way for a machine with
  no access to GitHub. A server installed from a checkout that is not a
  release tag -- `stable`, `main` -- has no attested archive, and
  `/plugins/NAME` says so; it serves one built from the code installed,
  marked as checked by no proof, only where its administrator allows it. What an install does with an archive a proof
  contradicts, or none can prove, is `trust`'s and the guards' (above).

## Later

Directions the rules leave room for, not yet decided:

- **A repository plugin.** The serving of plugins moves out of the API into a
  plugin of its own on the Xymon server: it fetches each release's archive
  and attestation, keeps several versions, and serves both, so that a
  machine without access to GitHub checks an archive offline against its
  attestation, and so that monitored hosts get their plugins from the
  server. `xymon-plugin` stays the command that installs the first plugin.
  Discussed in #29.
- **Working across installations.** Comparing their versions, installing
  into several in one run. Reading several is allowed -- `status` lists
  them all -- but nothing changes two installations in one run until then.
  Discussed in #39.
