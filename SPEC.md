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

**S4. A plugin has its side.**
The Xymon server (`server-*` lines: files under `$XYMONHOME/ext/NAME/`, a
xymonlaunch task, a section 8 manual page) and your own machine (`tools-*`
lines: files under `$PREFIX/libexec/xymon-plugins/NAME/`, commands in
`$PREFIX/bin`, a section 1 manual page). A plugin has one side or both. The
server side needs `XYMONHOME`, and without it installs nothing and says so.

### Installing, updating, removing

**S5. Installing enables nothing.**
A plugin's task is installed `DISABLED`; the install says how to enable it.

**S6. A plugin's task lives in its directory.**
It is `ext/NAME/tasks.cfg`, and `etc/tasks.d/NAME` is a link to it; under
`DESTDIR` the link names the installed file. A task file an older install
copied into `tasks.d` is moved into the plugin's directory as it was, and
replaced by the link. A link at `tasks.d/NAME` to something else is left as
it is, and the install refused.

**S7. An update replaces the code and keeps the choices.**
Installing again replaces the plugin's directory as a whole, so a file a
newer version no longer ships is gone; it keeps the task file the
administrator enabled, and a web server snippet once written.

**S8. Removing takes away the plugin and its links.**
The removal takes away the plugin's directory, its task link and its manual
pages, and is refused while another installed plugin needs it (S3).

**S9. Removing the directory by hand removes the task.**
Once `ext/NAME` is deleted, xymonlaunch no longer has the plugin's task, and
says nothing of the link left pointing nowhere; the next removal takes that
link away.

**S10. The administrator's data outlives the plugin.**
The removal keeps the web server snippets and the API's tokens file, and
says what it kept and how to remove it.

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

  With no plugin named, a verb acts on every plugin of the side. The side is
  the Xymon server when `XYMONHOME` is set, your own machine when it is not;
  `--server`, `--client` or `--tools` names it, and must when the command
  does not run on a terminal, so that a script never acts on a side it did
  not name. Run with no verb on a terminal, it asks what to do. It is POSIX
  `sh` and needs no `make`.
- **A plugin names the Xymon it needs.** A `xymon:` line in `PLUGIN` gives
  the lowest Xymon version the plugin works with. `install` compares it with
  the Xymon of the side: older, refused, naming both versions, unless
  `--force` is given, which installs it and says so, as a distribution may
  carry a feature back to an older number; not known, installed with a
  warning that it could not be checked; a development version, `4.3.32-dev`,
  counts as the release it leads to. A plugin that needs a newer Xymon for
  one feature alone says so in its README instead.
- **A plugin is on when its link is there.** A plugin's task is on when
  `etc/tasks.d/NAME` exists, and off when it is absent; `enable` makes the
  link, `disable` removes it, and the task file no longer carries
  `DISABLED`. An installation where it does is moved to the link by the next
  install.
- **`status` says what is installed.** For each plugin of a side: whether it
  is installed, its version from `VERSION`, whether it is on, and, against a
  checkout, whether a newer version is there.
- **A monitored host is a side.** `client-*` lines: a task the Xymon client
  starts from `clientlaunch.d`, linked as on the server. The checks under
  `checks/`, copied into place by hand today, each move under `plugins/`
  when they get a `PLUGIN` file, and `checks/` is empty once all have.
- **Removing the directory by hand removes everything of the plugin.**
  Beyond the task (S9), what each program reads it reads through the place
  below, so that after `ext/NAME` is deleted Xymon no longer applies the
  plugin's settings, the web server still starts, without its snippet, and
  the API no longer serves it:

  | What | Lives in | Seen by its reader through |
  |---|---|---|
  | settings | `ext/NAME/xymonserver.cfg` | a link in `etc/xymonserver.d/`, which Xymon reads after `xymonserver.cfg` |
  | manual page | `ext/NAME/` | a link in `MANDIR` |
  | web server snippet | `ext/NAME/` | an include the web server skips when the file is gone (`IncludeOptional` for Apache, a wildcard `include` for nginx) |
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
