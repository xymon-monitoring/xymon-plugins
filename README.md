# xymon-plugins

Plugins and extensions for the [Xymon](https://github.com/xymon-monitoring/xymon)
monitoring system: what people have written to make Xymon watch more, or
to read it from elsewhere, kept in one place with its tests, its manual
pages and one way to install. Xymon's own tree holds Xymon; this one holds
what builds on it.

## Structure

```
plugins/NAME/     one plugin: PLUGIN, README.md, its manual page, its code, tests/
checks/NAME/      one check: its script, its clientlaunch.cfg stanza, README
install.sh        installs, updates and removes the plugins, on either side
tests/            how the plugins fit together (compat/), the eval set, helpers
build/            CI's helpers: the contract check
SPEC.md           the rules of the plugin model, each enforced by a test
UPGRADING.md      what a change that breaks something asks of you
CONTRIBUTING.md   how a change is made and reviewed; AGENTS.md, what a coding agent adds
```

Two kinds of code live here, and [`plugins/README.md`](plugins/README.md)
and [`checks/README.md`](checks/README.md) list each kind:

- a **plugin** is a directory under `plugins/` with a `PLUGIN` file, a
  README, a manual page, tests, and the code, versioned on its own and
  installed with `install.sh`;
- a **check** is a directory under `checks/`, a script with its
  `clientlaunch.cfg` stanza and a README, copied into place by hand. The
  checks are the older half, and move under `plugins/` as each gets a
  `PLUGIN` file.

The `plugins/` half was the repository `xymon-api`, then `bonomani/xymon-plugins`,
and carries its whole history.

## Where things run

Whatever its kind, code in this repository runs in one of three places, and
Xymon has names for the first two:

| place | Xymon's name | started by | lives in |
|---|---|---|---|
| the Xymon server | server extension | xymonlaunch, from a file in `tasks.d` | `$XYMONHOME/ext` |
| a monitored host | client extension | the Xymon client, from `clientlaunch.cfg` | the client's `ext/` |
| your own machine | -- | you, or your AI tool | `~/.local` |

"Client" in these pages means Xymon's client, on a monitored host; a program
that calls the Xymon API is an *API client*; Claude Code, Codex, opencode and
the like are *AI tools*. What runs on the first two places is started by
Xymon itself, as its own user; what runs on your own machine is yours to
start, and reaches the server as each plugin's README says.

## What a plugin is

A directory under `plugins/` with a `PLUGIN` file, whose comments name every
key. What a plugin is, where it installs, and what installing, updating and
removing it guarantee are the rules of [`SPEC.md`](SPEC.md); how versions
move and how a change is made is in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Conventions

- **Install actions** name the side: `install-server`, `uninstall-server`,
  `venv-server` on the Xymon server; `install-tools`, `uninstall-tools`,
  `venv-tools` on your own machine. `install-client` is refused, naming
  `install-tools`: a client is Xymon's, on a monitored host, and the action
  of that name arrives with the first check that installs there.
- **Manual pages.** Section 8 for what runs on the server, section 1 for the
  commands; every behaviour and setting is in the page, the README says how
  to install and use.
- **Tests.** Each plugin's under its `tests/`; how the plugins fit together
  under `tests/compat/`. How to run them is in
  [`CONTRIBUTING.md`](CONTRIBUTING.md#tests).

## Getting the code

Take the branch `stable`: the newest code every test passed, which CI moves
forward. `main` holds every change as it lands.

```sh
git clone --branch stable https://github.com/xymon-monitoring/xymon-plugins   # update later with git pull
```

or the [tarball](https://github.com/xymon-monitoring/xymon-plugins/archive/refs/heads/stable.tar.gz)
or [zip](https://github.com/xymon-monitoring/xymon-plugins/archive/refs/heads/stable.zip).
A clone is the better choice: it updates with `git pull`, and
`git fetch -q && git log --oneline HEAD..origin/stable` says what an update
would bring.

## Installing

```sh
XYMONHOME=/usr/lib/xymon/server ./install.sh install-server NAME   # on the Xymon server
./install.sh install-tools NAME                                     # on your own machine
```

With no `NAME`, every plugin of that side. What each command puts where,
Python and the virtualenv, enabling, updating and uninstalling are in
[`plugins/README.md`](plugins/README.md#installing-a-plugin); each plugin's
README says only what is particular to it.

## Contributing and licence

[`CONTRIBUTING.md`](CONTRIBUTING.md) says how to change this code, and
[`AGENTS.md`](AGENTS.md) what a coding agent adds to it. Everything under `plugins/`, and the build and tests, is
under the GNU General Public License version 2 or, at your option, any later
version (`GPL-2.0-or-later`); the text of version 2 is in
[`LICENSE`](LICENSE). The checks under `checks/` each keep their own licence: see
[Licensing & provenance](checks/README.md#licensing--provenance).
