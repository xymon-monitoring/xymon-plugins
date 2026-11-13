# Contributing to xymon-plugins

Patches are welcome. This file covers what is easy to get wrong because it is
not visible from the source tree. Most of how a change is written, titled,
described and reviewed is the same as for Xymon itself, and is not repeated
here: the next section says which of Xymon's rules apply as they are. The
rest of this file is what differs, and what only this repository has.

## What applies as Xymon writes it

These sections of Xymon's
[`CONTRIBUTING.md`](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md)
apply here as written, with "the tree" meaning this repository:

- [Where a change gets written down](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#where-a-change-gets-written-down),
  for its principle -- a fact belongs where its reader is, and every other
  place points at it -- not for `Changes` and `RELEASENOTES`, which this
  repository does not have;
- [Shortening](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#shortening);
- [Titles](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#titles),
  with this repository's components (below);
- [Descriptions](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#descriptions),
  [Pre-review](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#pre-review)
  and [Reviews](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#reviews),
  for a change that goes through a pull request;
- [The last pass](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#the-last-pass),
  for every change;
- [Style](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#style).

From its Pull requests section, these hold here too: one change per commit,
each commit standing alone and saying what it does and why; say what you
verified and how; and each observable behaviour gets a test that fails
without it, checked by reverting what makes it true.

## What differs here

- **No `Changes`, no `RELEASENOTES`.** What an admin upgrading needs to know
  goes in [`UPGRADING.md`](UPGRADING.md) (see
  [Breaking changes](#breaking-changes)), and in the manual page when it
  changes how the plugin behaves.
- **Manual pages have no HTML copy.** Each plugin's page -- `xymonapi.8`,
  `xymonapi-mcp.1`, `xymonapi-rag.1` -- is the only copy: edit it, nothing
  is generated. Its `.TH` line's date changes with the plugin's version (see
  [Versions](#versions)).
- **No branch protection.** Changes may be pushed to `main` directly; a pull
  request is welcome, and is the way when you want a second reader.
- **Python, not C.** See [Python](#python) below; Xymon's C section does not
  apply.
- **Components, for titles and commit subjects:** a plugin's name
  (`xymonapi:`, `xymonapi-mcp:`, `xymonapi-rag:`, `xymonapi-agent:`), or one of `tests:`,
  `build:`, `README:`, `ci:`.
- **Surfaces**, in the sense of Xymon's table of who reads what:

  | surface | who reads it | what it carries |
  |---|---|---|
  | `README.md` | whoever arrives at the repository | what the plugins are, a quick start, where to read more |
  | a plugin's `README.md` | whoever installs, packages or uses that plugin, with the repository open | how to install it and use it |
  | a plugin's manual page | an admin, or a laptop user, with the plugin installed | its behaviour and every setting |
  | `plugins/xymonapi/openapi.yaml` | whoever writes a client or another implementation of the API | the contract: each path's answers, the closed list of errors, the numbered rules |
  | a plugin's `PLUGIN` file | `install.sh`, and whoever packages it | its name, side, version, what it needs, and what it installs |
  | `SPEC.md` | whoever changes the installer or adds a plugin | the plugin model's numbered rules, each enforced by a test |

## What only this repository has

### Plugins

What a plugin is, and what the installer guarantees, are the rules of
[`SPEC.md`](SPEC.md); how its rules are numbered and tested is at its top.

Code shared by two plugins lives in one of them, the one
it belongs to, and the other installs that one: the API's client,
`xymonapi_client.py`, is `xymonapi`'s. A plugin's README and manual page name the
plugins it uses, never those that use it: a new plugin built on another
changes nothing of that one.

### Versions

A plugin's version is the `version:` line of its `PLUGIN` file, `X.Y.Z`.
The install writes it beside the installed files, in `VERSION`, and
`/health` gives the API's. It changes when compatibility does, in the same
commit as the change: the last number for an addition, the first for a
change that breaks something for users or for another plugin. Other changes
leave it alone.

The plugins that read the API through `xymonapi_client.py` --
`xymonapi-mcp` and `xymonapi-rag` -- name in their `PLUGIN` files the lowest
`xymonapi` version they need; the client repeats it as `API_FLOOR`, and a test checks
that the three agree, so change them together. A client raises its floor
only to a version the API already has.

### Breaking changes

A change that breaks something adds, in the same commit, a section to
[`UPGRADING.md`](UPGRADING.md): the plugin, its new version, what breaks and
what to do. For the API's contract, CI checks it (`build/contract-check.sh`):
a change to `openapi.yaml` needs a new version of `xymonapi`, one that
`oasdiff` finds breaking needs a new major number and a section in
`UPGRADING.md`, and the run's summary prints the contract's changelog as a
draft. A behaviour that breaks outside the contract is for you to see.

### stable

`main` takes every change. When every check of a push to `main` passes, CI
moves the branch `stable` forward to it, never back: `stable` is the newest
code everything passed, and what outside users install. There are no release tags; to publish one, tag `stable`'s commit
`NAME/vX.Y.Z` with the plugin's version.

### The contract

`plugins/xymonapi/openapi.yaml` is the API's contract. A change to what a
client can observe -- a path, a parameter, a field, a status, an error --
changes it in the same commit. Its errors are a closed list: a new one is
added there first.

A behaviour the paths alone do not say is a numbered rule in its
description, `C1.`, `C2.`, and so on. A test that checks a rule cites it in
its message, as `[C3]`; `plugins/xymonapi/tests/xymonapi-clauses.sh` fails when a rule is
cited by no test, or a test cites a rule that does not exist. A new rule
therefore comes with its test, and a rule removed takes its citations with
it. Numbers are not reused.

The spec's `info.version` stays `1.0.0` until the API is first published.

### Python

- What runs on a laptop uses the standard library alone:
  `plugins/xymonapi/xymonapi_client.py`, which the MCP server and
  `xymonapi-rag` both load, and the MCP server itself, which speaks the
  protocol without the `mcp` package. Nothing is installed there but the
  plugins.
- A new module dependency goes in that plugin's `requirements.txt`, and only
  when a few lines of the standard library will not do.
- Python 3.9 is the floor; nothing newer is assumed.
- Keep `ruff check` quiet on the lines you change. Older warnings in a file
  you touch are a note for another change, not this one.

## Tests

The tests run against a server build of Xymon's current `main`, named by
`XYMON_SRC`, and use its test helpers:

```sh
XYMON_SRC=/path/to/built/xymon tests/run.sh                      # every test
XYMON_SRC=/path/to/built/xymon tests/run.sh plugins/<name>/tests # one plugin's
```

A test belongs to the plugin it checks, under `plugins/<name>/tests/`, and
may start the plugins that one requires, never others: `xymonapi-mcp`'s
tests start an API, `xymonapi`'s start nothing of the other plugins. A test
of how the plugins fit together -- installing them all, installing from
the server's `/plugins`, the floors agreeing -- goes under `tests/compat/`. Helpers
shared by several tests are under `tests/lib/`. Each test says at its top
what it checks and what it needs.
Unlike Xymon's, a test here may use Python: a helper written in Python goes
under `tests/lib/`, as `fake-llm.py` and `ctrl-c.py` do. Otherwise the test
scripts, and `install.sh`, keep to Xymon's portability rules -- bash 3.2, portable tool flags,
no early-exit pipes -- which `tests/compat/xymonapi-portability.sh` checks
with Xymon's own check, read from `XYMON_SRC`. A test that cannot
run where something it needs is missing skips, with exit 77, and says what.

## Copyright and licensing

Everything here is under the GNU General Public License version 2 or, at
your option, any later version (`GPL-2.0-or-later`); the text of version 2 is
in [`LICENSE`](LICENSE). Copyright in a contribution stays with its author.
Do not copy third-party code in without checking that its licence is
compatible and keeping its notices.

Coding agents: read [`AGENTS.md`](AGENTS.md) as well.
