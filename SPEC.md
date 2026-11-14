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
  directory, or a file that program reads only when it exists.
- **Removing the directory removes the plugin.** Deleting `ext/NAME` by hand
  is a valid way to take a plugin away: no task of it runs, no setting of it
  applies, nothing of it is served, and no program reports an error. What is
  left is at most a link that points nowhere, which every reader skips, and
  which the next removal takes away.
- **Installing does not enable.** An install puts the files in place and
  changes nothing that runs; switching a plugin on is a step of its own, and
  so is switching it off.
- **What the administrator chose survives an update.** Installing again
  replaces a plugin's code and keeps whether it is on, and its settings.
- **What the administrator wants to keep lives outside.** Data that should
  outlive the plugin -- the API's tokens, a search index -- is kept outside
  its directory, and does nothing once the plugin is gone.
- **One command, nothing particular to a plugin.** The command reads each
  plugin's `PLUGIN` file and holds no plugin's name; a new plugin is a
  directory and its `PLUGIN` file.
- **Every rule is enforced by a test**, so a change that breaks one fails at
  once.

## Rules

### What a plugin is

**S1. A plugin is a directory with a `PLUGIN` file.**
`plugins/NAME/` holds the `PLUGIN` file, a README, a manual page per side,
tests and the code. `install.sh` installs every plugin from its `PLUGIN`
file, and names none.

**S2. A plugin carries its version.**
The `version:` line, `X.Y.Z`, moves as `CONTRIBUTING.md` (Versions) says. The
install writes beside the installed files, in `VERSION`, the plugin's
release tag when the checkout is at one, else that version.

**S3. A plugin names the plugins it needs.**
Its `needs:` line names them; the install of a plugin installs them with it,
and its removal is refused while an installed plugin needs it, naming that
plugin.

**S14. A plugin names the Xymon it needs.**
A `xymon:` line in `PLUGIN`, `X.Y.Z`, gives the lowest Xymon version the
plugin's server side works with. `install-server` compares it with what
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
instead. Whatever the version, `install-server` says so when the server's
`xymonserver.cfg` does not read `xymonserver.d/`, where the plugins'
settings go: a configuration kept from before 4.3.31 ignores them.

**S4. A plugin has its side.**
The Xymon server (`server-*` lines: files under `$XYMONHOME/ext/NAME/`, a
xymonlaunch task, a section 8 manual page) and your own machine (`tools-*`
lines: files under `$PREFIX/libexec/xymon-plugins/NAME/`, commands in
`$PREFIX/bin`, a section 1 manual page). A plugin has one side or both. The
server side needs `XYMONHOME`, and without it installs nothing and says so.

**S18. A server action acts only on a server's tree.**
The tree `XYMONHOME` names is read for Xymon's marks, a whole pair counting
before any single mark: a server's, `etc/xymonserver.cfg` and `bin/xymond`,
which wins when a client's files are there too; else a client's,
`etc/xymonclient.cfg` and `bin/xymonclient.sh`. A client's tree, a tree with
one mark of a pair, and a tree with no marks are refused before anything
changes, naming the marks found or missing. Under `DESTDIR`, a staging
target, the marks are not read. Without `XYMONHOME`, the Xymon trees found
on the machine are named, and none is chosen.

### Installing, updating, removing

**S5. Installing enables nothing.**
A plugin's task is installed off, with no link (S13); the install says how
to turn it on.

**S6. A plugin's task lives in its directory.**
It is `ext/NAME/tasks.cfg`, and `etc/tasks.d/NAME`, when there, is a link to
it; under `DESTDIR` the link names the installed file. A regular file at
`tasks.d/NAME` -- a copy an older install made, or the file an editor left
in place of the link -- is the one xymonlaunch reads: it is moved into the
plugin's directory as it was, and linked unless it was `DISABLED`. A link
at `tasks.d/NAME` to something else is left as it is, and the install,
before it installs anything, `enable-server` and `disable-server` refused.

**S7. An update replaces the code and keeps the choices.**
Installing again replaces the plugin's directory as a whole, so a file a
newer version no longer ships is gone; it keeps the task file as the
administrator left it, whether it is on, and the web server snippets as the
administrator edited them.

**S8. Removing takes away the plugin and its links.**
The removal takes away the plugin's directory, its task link and its manual
pages, and is refused while another installed plugin needs it (S3).

**S9. Removing the directory by hand removes the task.**
Once `ext/NAME` is deleted, xymonlaunch no longer has the plugin's task, and
says nothing of the link left pointing nowhere; the next removal takes that
link away.

**S10. The administrator's data outlives the plugin.**
The removal keeps the API's tokens file, and says what it kept.

**S16. A plugin's web server snippet lives in its directory.**
A snippet the `conf:` line of `PLUGIN` names is installed in `ext/NAME/`,
and the web server is told to include it in a way that skips it once it is
gone: `IncludeOptional` on Apache, a wildcard `include` on nginx and
lighttpd. Removing the plugin, or deleting `ext/NAME`, removes it, and the
web server still starts. A snippet an older install wrote in `etc/` is left
there, since a web server may still include it, and copied, edits and all,
into `ext/NAME` by the next install, which says so.

**S13. A plugin is on when its link is there.**
A plugin's task is on when `etc/tasks.d/NAME` links to its task file, and
off when the link is absent: xymonlaunch has the task exactly then.
`enable-server` makes the link, `disable-server` removes it, and each says
so when there is nothing to do. The task file carries no `DISABLED`: one an
older install wrote with that line is off, and the line is taken out, and
the install says how to turn it on.

**S19. `/plugins` serves only what a plugin declares.**
What a server stages for `/plugins`, in `ext/xymon-plugins-dist`, is for
each plugin its `PLUGIN` file, its `README.md`, and the files, manual
pages, task and web server snippets its `PLUGIN` file names, with
`install.sh` and `LICENSE`: a file left beside them in the checkout is not
served. Each install prunes what is staged to the same, and to the
plugins installed on the server, before staging, so that what an older
install staged, or a plugin since renamed or removed left, is not served
either; a link in the stage is removed, never written through, and a
removal that fails stops the install. A name with a `/`, `.` or `..`, in
a plugin's files or in `needs:`, or a plugin file that is a link, stops
the install before anything is copied.

### Knowing what is installed

**S15. `status` says what is installed.**
`status-server` and `status-tools` say, for each plugin of the side, or
those named: whether it is installed, the version installed, from its
`VERSION`, a release tag read as its `X.Y.Z`; on the server, whether its
task is on; and the version of the checkout run from, marked newer when it
is. A name that is no plugin is refused. `status` changes nothing.

### Running the command

**S17. With no verb and no terminal, nothing is done.**
Run with no verb, its input or its output not on a terminal, the command
prints its usage, exits 2 and changes nothing, settings given or not: a
script that forgot its verb installs, enables and removes nothing.

### Getting the code

**S11. `stable` is code every test passed.**
CI moves `stable` to a commit of `main` once every test passed on it, forward
only; installing from `stable` installs tested code.

**S12. The installer runs on every machine a plugin goes to.**
`install.sh` and the tests keep to Xymon's portability rules, but the one
against Python, which every plugin needs.

## Planned

Rules decided but not yet tested; each is numbered in the pull request that
brings its test.

- **One command, read as a sentence.** `xymon-plugin`, at the top of the
  repository, replaces `install.sh`, and takes a verb and the plugins it
  acts on:

  ```sh
  ./xymon-plugin install xymonapi
  ./xymon-plugin enable xymonapi
  ./xymon-plugin disable xymonapi
  ./xymon-plugin update xymonapi
  ./xymon-plugin remove xymonapi
  ./xymon-plugin status
  ```

  With no plugin named, a verb acts on every plugin of the installation it
  targets (below). `--tools` asks for your own commands, under `PREFIX`; a
  server or client profile is the one the targeted installation's kind
  says. It is POSIX `sh` and needs no `make`.
- **A run acts on one Xymon installation, which `XYMONHOME` alone names.**
  An installation is a Xymon tree, a server's, marked by
  `etc/xymonserver.cfg` and `bin/xymond`, or a standalone client's, marked
  by `etc/xymonclient.cfg` and `bin/xymonclient.sh`. A server's own client
  tree, the `XYMONCLIENTHOME` its `xymonserver.cfg` names, belongs to that
  server. A machine may hold several installations, and a run acts on one.
  `XYMONHOME` is the only thing that chooses it -- running under `xymoncmd`,
  which sets it, counts as naming it -- and it is checked against its marks
  (S18). Detection -- the tree holding the current directory, `ext/`
  included, the trees of a running `xymonlaunch`, the packages' usual paths,
  the `xymon` user's home -- only proposes: it gives the dialogue its
  default, the tree holding the current directory first, else the only
  installation found, else none, and the person confirms. Off a terminal,
  without `XYMONHOME`, a server or client profile is refused, listing the
  trees found: a script's target depends neither on its current directory
  nor on what runs at that moment. Your own commands under `PREFIX` are a
  question of their own, never a fallback for a missing tree. Every run says
  on its first line the target and what chose it. Discussed in #39, where
  what an install records of its target is still open.
- **With no verb on a terminal, the command asks, then runs what it says.**
  Run with no verb, its input and its output on a terminal, it asks for a
  verb, then for the installation, by the rule above, then for the plugins.
  For an install, Enter takes every plugin of it, and the plugins a chosen
  one needs are added, each named (S3). A removal has no default, and a
  plugin another installed one needs is refused, naming it (S8), not
  removed with it. The dialogue then prints the command its answers spell,
  asks `Proceed? [Y/n]`, and on yes runs exactly that command and nothing
  else: it adds no behaviour of its own, and an install it runs enables
  nothing (S5). Off a terminal, S17.
- **A monitored host is a side.** `client-*` lines: a task the Xymon client
  starts from `clientlaunch.d`, linked as on the server. The checks under
  `checks/`, copied into place by hand today, each move under `plugins/`
  when they get a `PLUGIN` file, and `checks/` is empty once all have.
- **Removing the directory by hand removes everything of the plugin.**
  Beyond the task (S9), what each program reads it reads through the place
  below, so that after `ext/NAME` is deleted Xymon no longer applies the
  plugin's settings, and the API no longer serves it:

  | What | Lives in | Seen by its reader through |
  |---|---|---|
  | settings | `ext/NAME/xymonserver.cfg` | a link in `etc/xymonserver.d/`, which Xymon reads after `xymonserver.cfg` |
  | manual page | `ext/NAME/` | a link in `MANDIR` |
  | what `/plugins` serves | `ext/NAME/`, the release archive it was installed from | the API, serving that archive at `/plugins/NAME` |
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
  installed, not one built on the spot. `install` from a server checks the
  archive before it installs, by any proof that does not come from that
  server: its attestation, verified with `gh`, `cosign` or Python's
  `sigstore`, with no key kept, as the attestation is signed for the CI run
  that built the archive; or the same archive rebuilt from the release tag
  in a copy of the repository, from any mirror, the way for a machine with
  no access to GitHub. It refuses an archive that a proof contradicts, and
  one it can prove by no means unless `--force` is given. A server installed
  from a checkout that is not a release tag -- `stable`, `main` -- has no
  attested archive: `/plugins/NAME` says so, and an install from it needs
  `--force`.

## Later

Directions the rules leave room for, not yet decided:

- **A repository plugin.** The serving of plugins moves out of the API into a
  plugin of its own on the Xymon server: it fetches each release's archive
  and attestation, keeps several versions, and serves both, so that a
  machine without access to GitHub checks an archive offline against its
  attestation, and so that monitored hosts get their plugins from the
  server. `xymon-plugin` stays the command that installs the first plugin.
  Discussed in #29.
- **Working across installations.** A `status` of every installation on the
  machine together, comparing their versions, installing into several in
  one run. Nothing acts on two installations at once until then. Discussed
  in #39.
