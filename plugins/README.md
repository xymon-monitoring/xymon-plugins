# Plugins

The plugins of [xymon-plugins](../README.md): each a directory here with a
`PLUGIN` file, a README, a manual page, tests and its code, installed with
[`install.sh`](../install.sh) at the repository's top. What a plugin is, and
the conventions they share, are in the [top README](../README.md).

## The plugins

Four today, one family: the Xymon API and what builds on it. How they fit
together, and what each needs, is in [`xymonapi`'s
README](xymonapi/README.md#the-api-and-what-builds-on-it); each plugin's
own README says how to install and use it, its manual page every behaviour
and setting.

| plugin | what it is |
|---|---|
| [`xymonapi`](xymonapi/README.md) | the Xymon API: a read-only HTTP and JSON interface to a Xymon server, with `xymonapi-connect` and a client library for the machines that read it |
| [`xymonapi-mcp`](xymonapi-mcp/README.md) | an MCP server that gives an AI tool read-only tools over the API |
| [`xymonapi-rag`](xymonapi-rag/README.md) | a search of Xymon's manual pages and history by meaning: the index on the server, `search` and `ask` anywhere |
| [`xymonapi-agent`](xymonapi-agent/README.md) | one command that asks an AI CLI a question about Xymon, with the MCP server as its only tool; on the server, the API's `/ask` |

## Getting the code from the server

A machine that will only read the API can take the code from the
Xymon server once the plugins are installed there, at the versions it runs:

```sh
curl --cacert ~/.config/xymon-api/xymon-ca.pem https://xymon.example.ch/xymon/api/v1/plugins | tar xz
```

The address is the API's URL as `xymonapi`'s README gives it for each way of
reaching it -- port included when it is not 443 -- followed by
`/xymon/api/v1/plugins`. `--cacert` names the server's certificate when it
is not one the machine trusts already; `xymonapi`'s README says where to get
it. Never `-k`: code
fetched without checking the certificate could be anyone's.

## Installing a plugin

Every plugin installs the same way, with `./install.sh` at the
repository's top -- a POSIX shell script, needing no `make` -- and each
README says only what is particular to it. A plugin has up to two sides, the
Xymon server's and your own machine's ([Where things run](../README.md#where-things-run)),
and you install the one the machine plays. The server actions are also
spelt without `-server`, as they were before the tools had a name of their
own; `install-client` is refused, naming `install-tools`: a client here is
Xymon's, on a monitored host, and nothing installs one there yet.

| side | where, as whom | command | puts |
|---|---|---|---|
| the Xymon server | the Xymon server, as the user that may write its directory, usually root | `XYMONHOME=/usr/lib/xymon/server ./install.sh install-server NAME` | the code in `$XYMONHOME/ext/NAME/`, its task in `ext/NAME/tasks.cfg`, written `DISABLED` and linked from `$XYMONHOME/etc/tasks.d/NAME`, its manual page under `MANDIR` (`/usr/share/man`) |
| your own machine | any machine that reads the API, the server included, as yourself | `./install.sh install-tools NAME` | the code in `$PREFIX/libexec/xymon-plugins/NAME/`, its command in `$PREFIX/bin`, its manual page in `$PREFIX/share/man/man1`; `PREFIX` is `~/.local` |

A plugin that needs another installs it first, so one command is enough,
and with no `NAME` the same two commands install every plugin of a side.
Settings are taken from the environment or as `NAME=value` arguments. `DESTDIR` stages either side for a package. The server install also
copies each plugin into what the API serves at `/plugins`, for other
machines to install from.

**Python.** Every plugin runs on Python 3.9 or later. Only those that need
modules beyond the standard library -- the `server-modules` and `tools-modules`
lines of its `PLUGIN` -- make
or complete a virtualenv; the others ask nothing about one, and run with it
when it is there. For a plugin that needs modules, when the machine already
has a Python with them -- the newest of `python3.14` down to `python3` on
PATH and in Homebrew's and pyenv's directories, or the one `PYTHON=` names
-- the install makes a virtualenv beside the plugins from it, `ext/venv` on
the server and `libexec/xymon-plugins/venv` elsewhere, pinning that
interpreter and fetching nothing. When no Python has them, or the virtualenv
there lacks some, the install run from a terminal offers to make or complete
it, installing the modules from PyPI -- the one virtualenv of that side,
with the modules of every plugin installed there; without a terminal, or
answered no, it says so, and `XYMONHOME=... ./install.sh venv-server PYTHON=...` on the
server, or `./install.sh venv-tools PYTHON=...` elsewhere, does it later. The
launchers run with `XYMONAPI_PYTHON` when it is set, else with that
virtualenv, else with the `python3` on PATH, asking nothing; a command that
then needs a module it lacks says which, and what installs it.

**Enabling.** A server task is installed `DISABLED`, so that installing
changes nothing until you remove that line from its file,
`ext/NAME/tasks.cfg` -- or `etc/tasks.d/NAME`, the link to it; xymonlaunch
notices and starts it. A later install leaves the task file as you left
it.

**Updating.** Run the same install again, from an updated checkout or a
fresh `/plugins` download. The server install replaces the plugin's code and
keeps your task file, snippets and settings. A task that runs on keeps the
code it loaded: the API's install stops the API, saying so, and xymonlaunch
starts the new; a task that runs from time to time, as the index, takes the
new code at its next run.

**Uninstalling.** `XYMONHOME=... ./install.sh uninstall-server NAME` or
`./install.sh uninstall-tools NAME` removes that plugin alone, and refuses
while another installed plugin needs it, naming it; with no `NAME`, every
plugin of the side and the virtualenv beside them. Each says what it keeps.
On the server, removing `$XYMONHOME/ext/NAME` by hand also removes the
plugin's task: xymonlaunch skips the link in `tasks.d` that now points
nowhere and stops the task at its next reload, within half a minute, with
nothing in its log. The link, the manual page and the copy served at
`/plugins` stay until `uninstall-server NAME`.
