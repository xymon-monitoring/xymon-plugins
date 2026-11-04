# Upgrading

What a change that breaks something asks of you, newest first: the plugin,
its version, what breaks, and what to do. Every other change needs nothing
but installing the new code (see each plugin's README). CI refuses a change
that breaks the API's contract without a line here.

## Every plugin's install, from xymonapi 2.2.0

The plugins install with `./install.sh` at the repository's top, and `make`
is no longer used: the `Makefile`s are gone. What was
`make install XYMONHOME=...` in `plugins/NAME` is
`XYMONHOME=... ./install.sh install-server NAME`, and the other targets are
the actions `./install.sh` lists; with no `NAME` they act on every plugin
of the side, as the top `Makefile` did.
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
