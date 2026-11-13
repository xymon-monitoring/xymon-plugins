# Upgrading

What a change that breaks something asks of you, newest first: the plugin,
its version, what breaks, and what to do. Every other change needs nothing
but installing the new code (see each plugin's README). CI refuses a change
that breaks the API's contract without a line here.

## Server tasks on and off, by a link, from xymonapi 2.4.0

A plugin's task is no longer turned on by removing `DISABLED` from its
file: it is on when `etc/tasks.d/NAME` links to `ext/NAME/tasks.cfg`, which
`XYMONHOME=... ./install.sh enable-server NAME` makes and `disable-server
NAME` removes. The first install with this version keeps each task as it
was: one still `DISABLED` stays off and loses that line, and says how to
turn it on; one you enabled stays on. A script that enabled a task by
editing its file runs `enable-server` instead.

## The install actions, from xymonapi 2.3.0

`./install.sh install-client`, `uninstall-client` and `venv-client` are now
`install-tools`, `uninstall-tools` and `venv-tools`: what they install are
the plugins' commands, on your own machine, and "client" is Xymon's word for
a monitored host. The old names are refused, saying the new one. The server
actions gain `-server` -- `install-server`, `uninstall-server`,
`venv-server` -- and keep their old spellings. What is installed, and where,
is unchanged: an install over the old one needs nothing more. In a
`PLUGIN` file, `client-files`, `client-manual`, `client-modules` and
`uninstalled-client` are `tools-files`, `tools-manual`, `tools-modules` and
`uninstalled-tools`. The directory the server stages the plugins in for
`/plugins`, `ext/xymon-plugins-client`, is `ext/xymon-plugins-dist`; a
server install renames nothing, so remove the old directory by hand after
the first install with this version, or leave it: nothing reads it.

## Every plugin's install, from xymonapi 2.2.0

The plugins install with `./install.sh` at the repository's top, and `make`
is no longer used: the `Makefile`s are gone. What was
`make install XYMONHOME=...` in `plugins/NAME` is
`XYMONHOME=... ./install.sh install NAME`; `make install-client`,
`make uninstall`, `make uninstall-client`, `make venv` and
`make venv-client` are the same words after `./install.sh`, and with no
`NAME` they act on every plugin of the side, as the top `Makefile` did.
`PREFIX`, `MANDIR`, `DESTDIR` and `PYTHON` mean what they meant, from the
environment or as `NAME=value` arguments. What is installed, and where, is
unchanged: an install over the old one needs nothing more. The tests run
with `tests/run.sh` instead of `make test`.

## xymonapi 2.0.0

An API started before its launcher named it by its full path -- one whose
`pgrep -lf app.py` line shows a bare `app.py` -- is not found by the install,
which from now on stops the running API itself, and keeps running the old
code. Stop it once by its number, `kill PID`; xymonlaunch starts the new
one, which the next install finds.

`/client` is now `/plugins`, what it gives unchanged: the plugins installed
on the server, as a `.tar.gz`. Machines already installed need nothing; one
downloading the code from the server asks for
`https://SERVER/xymon/api/v1/plugins` instead.

## xymonapi 1.0.0

`/client` gives the code of the plugins installed on the server, as a
`.tar.gz`, instead of a setup script; its `name` and `format` options, and
the settings `XYMONAPI_PUBLIC_URL` and `XYMONAPI_REPO`, are gone. Machines
already set up keep their token and registrations and need nothing. To set
up one, or redo it: get the code -- from `/client` or a clone -- run
`make install-client` in `plugins/xymonapi-mcp`, then
`xymonapi-mcp register URL` (or `xymonapi-connect URL` for the API alone).
On the server, `make install` at the repository's top now also stages
`xymonapi-mcp` there, for `/client`.

## xymonapi-mcp, xymonapi-rag 0.1.0

The clients send a token and nothing else: `XYMONAPI_USER`,
`XYMONAPI_PASSWORD` and `XYMONAPI_PASSWORD_FILE` are no longer read. A
machine set up with a password gets 401: run `xymonapi-connect`, which gets
it a token.

## xymonapi 0.1.0

A user removed from the password file loses every client token at the first
use of one; putting the user back does not bring them back. Each of that
user's machines runs `xymonapi-connect` again for a new token.
